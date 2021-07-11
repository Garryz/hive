local cell = require "cell"
local socket = require "http.sockethelper"
local internal = require "http.internal"

local string = string
local table = table

local httpc = {}

local function check_protocol(host)
    local protocol = host:match "^[Hh][Tt][Tt][Pp][Ss]?://"
    if protocol then
        host = string.gsub(host, "^" .. protocol, "")
        protocol = string.lower(protocol)
        if protocol == "https://" then
            return "https", host
        elseif protocol == "http://" then
            return "http", host
        else
            error(string.format("Invalid protocol: %s", protocol))
        end
    else
        return "http", host
    end
end

local SSLCTX_CLIENT = nil
local function gen_interface(protocol, sock)
    if protocol == "http" then
        return {
            init = nil,
            close = nil,
            read = socket.readfunc(sock),
            write = socket.writefunc(sock),
            readall = function()
                return socket.readall(sock)
            end
        }
    elseif protocol == "https" then
        local tls = require "http.tlshelper"
        SSLCTX_CLIENT = SSLCTX_CLIENT or tls.newctx()
        local tls_ctx = tls.newtls("client", SSLCTX_CLIENT)
        return {
            init = tls.initrequestfunc(sock, tls_ctx),
            close = tls.closefunc(tls_ctx),
            read = tls.readfunc(sock, tls_ctx),
            write = tls.writefunc(sock, tls_ctx),
            readall = tls.readallfunc(sock, tls_ctx)
        }
    else
        error(string.format("Invalid protocol: %s", protocol))
    end
end

function httpc.request(method, host, url, recvheader, header, content, timeout)
    local protocol
    protocol, host = check_protocol(host)
    local hostname, port = host:match "([^:]+):?(%d*)$"
    if port == "" then
        port = protocol == "http" and 80 or protocol == "https" and 443
    else
        port = tonumber(port)
    end
    local sock = socket.connect(hostname, port, timeout)
    if not sock then
        error(string.format("%s connect error host:%s, port:%s, timeout:%s", protocol, hostname, port, timeout))
    end
    local interface = gen_interface(protocol, sock)
    local finish
    if timeout then
        cell.timeout(
            timeout,
            function()
                if not finish then
                    socket.close(sock)
                    if interface.close then
                        interface.close()
                    end
                end
            end
        )
    end
    if interface.init then
        interface.init()
    end
    local ok, statuscode, body = pcall(internal.request, interface, method, host, url, recvheader, header, content)
    finish = true
    socket.close(sock)
    if interface.close then
        interface.close()
    end
    if ok then
        return statuscode, body
    else
        error(statuscode)
    end
end

function httpc.get(host, url, recvheader, header, timeout)
    return httpc.request("GET", host, url, recvheader, header, nil, timeout)
end

local function escape(s)
    return (string.gsub(
        s,
        "([^A-Za-z0-9_])",
        function(c)
            return string.format("%%%02X", string.byte(c))
        end
    ))
end

function httpc.post(host, url, form, recvheader, timeout)
    local header = {
        ["content-type"] = "application/x-www-form-urlencoded"
    }
    local body = {}
    for k, v in pairs(form) do
        table.insert(body, string.format("%s=%s", escape(k), escape(v)))
    end

    return httpc.request("POST", host, url, recvheader, header, table.concat(body, "&"), timeout)
end

return httpc
