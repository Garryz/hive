local internal = require "http.internal"
local socket = require "socket"
local crypt = require "crypt"
local httpd = require "http.httpd"
local sockethelper = require "http.sockethelper"
local env = require "env"
local log = require "log"

local GLOBAL_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
local MAX_FRAME_SIZE = 256 * 1024 -- max frame is 256K

local CERT_FILE = env.getconfig("certfile") or "./server-cert.pem"
local KEY_FILE = env.getconfig("keyfile") or "./server-key.pem"

local M = {}

local function write_handshake(self, host, url, header)
    local key = crypt.base64encode(crypt.randomkey() .. crypt.randomkey())
    local request_header = {
        ["Upgrade"] = "websocket",
        ["Connection"] = "Upgrade",
        ["Sec-WebSocket-Version"] = "13",
        ["Sec-WebSocket-Key"] = key
    }
    if header then
        for k, v in pairs(header) do
            assert(request_header[k] == nil, k)
            request_header[k] = v
        end
    end

    local recvheader = {}
    local code, body = internal.request(self.interface, "GET", host, url, recvheader, request_header)
    if code ~= 101 then
        error(string.format("websocket handshake error: code[%s] info:%s", code, body))
    end

    if not recvheader["upgrade"] or recvheader["upgrade"]:lower() ~= "websocket" then
        error("websocket handshake upgrade must websocket")
    end

    if not recvheader["connection"] or recvheader["connection"]:lower() ~= "upgrade" then
        error("websocket handshake connection must upgrade")
    end

    local sw_key = recvheader["sec-websocket-accept"]
    if not sw_key then
        error("websocket handshake need Sec-WebSocket-Accept")
    end

    local guid = self.guid
    sw_key = crypt.base64decode(sw_key)
    if sw_key ~= crypt.sha1(key .. guid) then
        error("websocket handshake invalid Sec-WebSocket-Accept")
    end
end

local function read_handshake(self, upgrade_ops)
    local header, method, url
    if upgrade_ops then
        header, method, url = upgrade_ops.header, upgrade_ops.method, upgrade_ops.url
    else
        local tmpline = {}
        local header_body = internal.recvheader(self.interface.read, tmpline, "")
        if not header_body then
            return 413
        end

        local request = assert(tmpline[1])
        local httpver
        method, url, httpver = request:match "^(%a+)%s+(.-)%s+HTTP/([%d%.]+)$"
        assert(method and url and httpver)
        if method ~= "GET" then
            return 400, "need GET method"
        end

        httpver = assert(tonumber(httpver))
        if httpver < 1.1 then
            return 505 -- HTTP Version not supported
        end
        header = internal.parseheader(tmpline, 2, {})
    end

    if not header then
        return 400 -- Bad request
    end
    if not header["upgrade"] or header["upgrade"]:lower() ~= "websocket" then
        return 426, "Upgrade Required"
    end

    if not header["host"] then
        return 400, "host Required"
    end

    if not header["connection"] or not header["connection"]:lower():find("upgrade", 1, true) then
        return 400, "Connection must Upgrade"
    end

    local sw_key = header["sec-websocket-key"]
    if not sw_key then
        return 400, "Sec-WebSocket-Key Required"
    else
        local raw_key = crypt.base64decode(sw_key)
        if #raw_key ~= 16 then
            return 400, "Sec-WebSocket-Key invalid"
        end
    end

    if not header["sec-websocket-version"] or header["sec-websocket-version"] ~= "13" then
        return 400, "Sec-WebSocket-Version must 13"
    end

    local sw_protocol = header["sec-websocket-protocol"]
    local sub_pro = ""
    if sw_protocol then
        local has_chat = false
        for sub_protocol in string.gmatch(sw_protocol, "[^%s,]+") do
            if sub_protocol == "chat" then
                sub_pro = "Sec-WebSocket-Protocol: chat\r\n"
                has_chat = true
                break
            end
        end
        if not has_chat then
            return 400, "Sec-WebSocket-Protocol need include chat"
        end
    end

    -- response handshake
    local accept = crypt.base64encode(crypt.sha1(sw_key .. self.guid))
    local resp = "HTTP/1.1 101 Switching Protocols\r\n" .. "Upgrade: websocket\r\n" .. "Connection: Upgrade\r\n" ..
                     string.format("Sec-WebSocket-Accept: %s\r\n", accept) .. sub_pro .. "\r\n"
    self.interface.write(resp)
    return nil, header, url
end

local op_code = {
    ["frame"] = 0x00,
    ["text"] = 0x01,
    ["binary"] = 0x02,
    ["close"] = 0x08,
    ["ping"] = 0x09,
    ["pong"] = 0x0A,
    [0x00] = "frame",
    [0x01] = "text",
    [0x02] = "binary",
    [0x08] = "close",
    [0x09] = "ping",
    [0x0A] = "pong"
}

local function write_frame(self, op, payload_data, masking_key)
    payload_data = payload_data or ""
    local payload_len = #payload_data
    local op_v = assert(op_code[op])
    local v1 = 0x80 | op_v -- fin is 1 with opcode
    local s
    local mask = masking_key and 0x80 or 0x00
    -- mask set to 0
    if payload_len < 126 then
        s = string.pack("I1I1", v1, mask | payload_len)
    elseif payload_len <= 0xffff then
        s = string.pack("I1I1>I2", v1, mask | 126, payload_len)
    else
        s = string.pack("I1I1>I8", v1, mask | 127, payload_len)
    end
    self.interface.write(s)

    -- write masking_key
    if masking_key then
        s = string.pack(">I4", masking_key)
        self.interface.write(s)
        payload_data = crypt.xor_str(payload_data, s)
    end

    if payload_len > 0 then
        self.interface.write(payload_data)
    end
end

local function read_close(payload_data)
    local code, reason
    local payload_len = #payload_data
    if payload_len > 2 then
        local fmt = string.format(">I2c%d", payload_len - 2)
        code, reason = string.unpack(fmt, payload_data)
    end
    return code, reason
end

local function read_frame(self)
    local s = self.interface.read(2)
    local v1, v2 = string.unpack("I1I1", s)
    local fin = (v1 & 0x80) ~= 0
    -- unused flag
    -- local rsv1 = (v1 & 0x40) ~= 0
    -- local rsv2 = (v1 & 0x20) ~= 0
    -- local rsv3 = (v1 & 0x10) ~= 0
    local op = v1 & 0x0f
    local mask = (v2 & 0x80) ~= 0
    local payload_len = (v2 & 0x7f)
    if payload_len == 126 then
        s = self.interface.read(2)
        payload_len = string.unpack(">I2", s)
    elseif payload_len == 127 then
        s = self.interface.read(8)
        payload_len = string.unpack(">I8", s)
    end

    if self.mode == "server" and payload_len > MAX_FRAME_SIZE then
        error("payload_len is too large")
    end

    local masking_key = mask and self.interface.read(4) or false
    local payload_data = payload_len > 0 and self.interface.read(payload_len) or ""
    payload_data = masking_key and crypt.xor_str(payload_data, masking_key) or payload_data
    return fin, assert(op_code[op]), payload_data
end

local function resolve_accept(self, options)
    local code, err, url = read_handshake(self, options and options.upgrade)
    if code then
        local ok, s = httpd.writeresponse(self.interface.write, code, err)
        if not ok then
            error(s)
        end
    end
end

local function gen_interface(protocol, sock, tls_ctx)
    if protocol == "ws" then
        return {
            close = function()
                sockethelper.close(sock)
            end,
            read = sockethelper.readfunc(sock),
            write = sockethelper.writefunc(sock),
            readall = function()
                return socket.readall(sock)
            end
        }
    elseif protocol == "wss" then
        local tls = require "http.tlshelper"
        return {
            close = function()
                sockethelper.close(sock)
                tls.closefunc(tls_ctx)()
            end,
            read = tls.readfunc(sock, tls_ctx),
            write = tls.writefunc(sock, tls_ctx),
            readall = tls.readallfunc(sock, tls_ctx)
        }
    else
        error(string.format("Invalid protocol: %s", protocol))
    end
end

local websocket = {}

local websocket_meta = {
    __index = websocket,
    __gc = function(self)
        self.interface.close()
    end
}

function websocket:readmsg()
    local recv_buf
    while true do
        local fin, op, payload_data = read_frame(self)
        if op == "close" then
            local code, reason = read_close(payload_data)
            log.infof("%s close code %s reason %s", self.sock, code, reason)
            self.interface.close()
            return
        elseif op == "ping" then
            write_frame(self, "pong", payload_data)
        elseif op ~= "pong" then -- op is frame, text binary
            if fin and not recv_buf then
                return payload_data
            else
                recv_buf = recv_buf or {}
                recv_buf[#recv_buf + 1] = payload_data
                if fin then
                    local s = table.concat(recv_buf)
                    return s
                end
            end
        end
    end
end

function websocket:writemsg(data, fmt, masking_key)
    fmt = fmt or "text"
    assert(fmt == "text" or fmt == "binary")
    write_frame(self, fmt, data, masking_key)
end

function websocket:ping()
    write_frame(self, "ping")
end

function websocket:close(code, reason)
    local ok, err = xpcall(function()
        reason = reason or ""
        local payload_data
        if code then
            local fmt = string.format(">I2c%d", #reason)
            payload_data = string.pack(fmt, code, reason)
        end
        write_frame(self, "close", payload_data)
    end, debug.traceback)
    self.interface.close()
    if not ok then
        log.error(err)
    end
end

function websocket:onclose(callback)
    self.sock:onclose(callback)
end

local SSLCTX_CLIENT = nil
local function _new_client_ws(sock, protocol, hostname)
    local tls_ctx
    if protocol == "wss" then
        local tls = require "http.tlshelper"
        SSLCTX_CLIENT = SSLCTX_CLIENT or tls.newctx()
        tls_ctx = tls.newtls("client", SSLCTX_CLIENT, hostname)
        local init = tls.initrequestfunc(sock, tls_ctx)
        init()
    end

    local obj = {}
    obj.mode = "client"
    obj.sock = sock
    obj.guid = GLOBAL_GUID
    obj.interface = gen_interface(protocol, sock, tls_ctx)
    setmetatable(obj, websocket_meta)
    return obj
end

local SSLCTX_SERVER = nil
local function _new_server_ws(sock, protocol)
    local tls_ctx
    if protocol == "wss" then
        local tls = require "http.tlshelper"
        if not SSLCTX_SERVER then
            SSLCTX_SERVER = tls.newctx()
            -- gen cert and key
            -- openssl req -x509 -newkey rsa:2048 -days 3650 -nodes -keyout server-key.pem -out server-cert.pem
            SSLCTX_SERVER:set_cert(CERT_FILE, KEY_FILE)
        end
        local tls_ctx = tls.newtls("server", SSLCTX_SERVER)
        local init = tls.initresponsefunc(sock, tls_ctx)
        init()
    end

    local obj = {}
    obj.mode = "server"
    obj.sock = sock
    obj.guid = GLOBAL_GUID
    obj.interface = gen_interface(protocol, sock, tls_ctx)
    setmetatable(obj, websocket_meta)
    return obj
end

function M.accept(socket_id, protocol, addr, options)
    protocol = protocol or "ws"
    local sock = socket.bind(socket_id)
    local ws_obj = _new_server_ws(sock, protocol)
    ws_obj.addr = addr

    local ok, err = xpcall(resolve_accept, debug.traceback, ws_obj, options)
    if not ok then
        log.error(err)
        return
    end

    return ws_obj
end

function M.connect(url, header, timeout)
    local protocol, host, uri = string.match(url, "^(wss?)://([^/]+)(.*)$")
    if protocol ~= "wss" and protocol ~= "ws" then
        error(string.format("invalid protocol: %s", protocol))
    end

    assert(host)
    local host_addr, host_port = string.match(host, "^([^:]+):?(%d*)$")
    assert(host_addr and host_port)
    if host_port == "" then
        host_port = protocol == "ws" and 80 or 443
    end
    local hostname
    if not host_addr:match(".*%d+$") then
        hostname = host_addr
    end

    uri = uri == "" and "/" or uri
    local sock = sockethelper.connect(host_addr, host_port, timeout)
    local ws_obj = _new_client_ws(sock, protocol, hostname)
    ws_obj.addr = host
    write_handshake(ws_obj, host_addr, uri, header)
    return ws_obj
end

return M
