local cell = require "cell"
local socket = require "socket"
local log = require "log"

local coroutine = coroutine
local assert = assert
local pairs = pairs
local pcall = pcall
local table = table
local ipairs = ipairs
local type = type
local error = error

-- channel support auto reconnect , and capture socket error in request/response transaction
-- { host = "", port = , auth = function(so) , response = function(so) session, data }

local socket_channel = {}
local channel = {}
local channel_socket = {}
local channel_meta = {__index = channel}
local channel_socket_meta = {
    __index = channel_socket
}

local socket_error =
    setmetatable(
    {},
    {
        __tostring = function()
            return "[Error: socket]"
        end
    }
) -- alias for error object

function channel_socket:write(msg)
    local sock = self[1]
    if sock then
        return sock:write(msg)
    end
end

function channel_socket:close()
    local sock = self[1]
    self[1] = false
    if sock then
        sock:disconnect()
    end
end

channel_socket_meta.__gc = channel_socket.close

function channel_socket:readbytes(bytes)
    local sock = self[1]
    if sock then
        local result = sock:readbytes(bytes)
        if not result then
            error(socket_error)
        else
            return result
        end
    else
        error(socket_error)
    end
end

function channel_socket:readline(sep)
    local sock = self[1]
    if sock then
        local result = sock:readline(sep)
        if not result then
            error(socket_error)
        else
            return result
        end
    else
        error(socket_error)
    end
end

function socket_channel.channel(desc)
    local c = {
        __host = assert(desc.host),
        __port = assert(desc.port),
        __backup = desc.backup,
        __auth = desc.auth,
        __response = desc.response, -- It's for session mode
        __request = {}, -- request seq { response func }	-- It's for order mode
        __thread = {}, -- event seq or session->event map
        __result = {}, -- response result { event -> result }
        __result_data = {},
        __dispatch_thread = nil,
        __wait_response = nil,
        __connecting = {},
        __sock = false,
        __closed = false,
        __authcoroutine = false
    }

    return setmetatable(c, channel_meta)
end

local function wakeup_all(self, errmsg)
    if self.__response then
        for session, event in pairs(self.__thread) do
            self.__thread[session] = nil
            self.__result[event] = false
            self.__result_data[event] = errmsg
            cell.wakeup(event)
        end
    else
        for i = 1, #self.__request do
            self.__request[i] = nil
        end
        for i = 1, #self.__thread do
            local event = self.__thread[i]
            self.__thread[i] = nil
            if event then -- ignore the close signal
                self.__result[event] = false
                self.__result_data[event] = errmsg
                cell.wakeup(event)
            end
        end
    end
end

local function dispatch_by_session(self)
    local response = self.__response
    -- response() return session
    while self.__sock do
        local ok, session, result_ok, result_data = pcall(response, self.__sock)
        if ok and session then
            local event = self.__thread[session]
            if event then
                self.__thread[session] = nil
                self.__result[event] = result_ok
                self.__result_data[event] = result_data
                cell.wakeup(event)
            else
                log.error("socket: unknown session:", session)
            end
        else
            if self.__sock then
                self.__sock:close()
            end
            local errormsg
            if session then
                errormsg = session
            else
                errormsg = "[Error: socket]"
            end
            wakeup_all(self, errormsg)
        end
    end
end

local function pop_response(self)
    while true do
        local func, event = table.remove(self.__request, 1), table.remove(self.__thread, 1)
        if func then
            return func, event
        end
        self.__wait_response = cell.event()
        cell.wait(self.__wait_response)
    end
end

local function dispatch_by_order(self)
    while self.__sock do
        local func, event = pop_response(self)
        if not event then
            -- close signal
            wakeup_all(self, "channel_closed")
            break
        end
        local sock = self.__sock
        if not sock then
            -- closed by peer
            self.__result[event] = false
            self.__result_data[event] = "closed by peer"
            cell.wakeup(event)
            wakeup_all(self, "closed by peer")
            break
        end
        local ok, result_ok, result_data = pcall(func, sock)
        if ok then
            self.__result[event] = result_ok
            self.__result_data[event] = result_data
            cell.wakeup(event)
        else
            if self.__sock then
                self.__sock:close()
            end
            self.__result[event] = false
            self.__result_data[event] = result_ok
            cell.wakeup(event)
            wakeup_all(self, result_ok)
        end
    end
end

local function dispatch_function(self)
    if self.__response then
        return dispatch_by_session
    else
        return dispatch_by_order
    end
end

local function push_response(self, response, event)
    if self.__response then
        -- response is session
        self.__thread[response] = event
    else
        -- response is a function, push it to __request
        table.insert(self.__request, response)
        table.insert(self.__thread, event)
        if self.__wait_response then
            cell.wakeup(self.__wait_response)
            self.__wait_response = nil
        end
    end
end

local function term_dispatch_thread(self)
    if not self.__response and self.__dispatch_thread then
        -- dispatch by order, send close signal to dispatch thread
        push_response(self, true, false) -- (true, false) is close signal
    end
end

local function connect_once(self)
    if self.__closed then
        return false
    end

    local addr_list = {}
    local addr_set = {}

    local function _add_backup()
        if self.__backup then
            for _, addr in ipairs(self.__backup) do
                local host, port
                if type(addr) == "table" then
                    host, port = addr.host, addr.port
                else
                    host = addr
                    port = self.__port
                end

                -- don't add the same host
                local hostkey = host .. ":" .. port
                if not addr_set[hostkey] then
                    addr_set[hostkey] = true
                    table.insert(addr_list, {host = host, port = port})
                end
            end
        end
    end

    local function _next_addr()
        local addr = table.remove(addr_list, 1)
        if addr then
            log.info("socket: connect to backup host", addr.host, addr.port)
        end
        return addr
    end

    local function _connect_once(self, addr)
        local sock, err = socket.connect(addr.host, addr.port)
        if not sock then
            -- try next once
            addr = _next_addr()
            if addr == nil then
                return false, err
            end
            return _connect_once(self, addr)
        end

        self.__host = addr.host
        self.__port = addr.port

        assert(not self.__sock and not self.__authcoroutine)
        -- term current dispatch thread (send a signal)
        term_dispatch_thread(self)

        while self.__dispatch_thread do
            -- wait for dispatch thread exit
            cell.yield()
        end

        sock:onclose(
            function(fd)
                if self.__sock and self.__sock[1] and self.__sock[1].__fd == fd then
                    self.__sock = false
                end
            end
        )
        self.__sock = setmetatable({sock}, channel_socket_meta)
        self.__dispatch_thread =
            cell.fork(
            function()
                pcall(dispatch_function(self), self)
                -- clear dispatch_thread
                self.__dispatch_thread = nil
            end
        )

        if self.__auth then
            self.__authcoroutine = coroutine.running()
            local ok, message = pcall(self.__auth, self)
            if not ok then
                if self.__sock then
                    self.__sock:close()
                end
                log.warning("socket: auth failed", message)
            end
            self.__authcoroutine = false
            if ok then
                if not self.__sock then
                    -- auth may change host, so connect again
                    return connect_once(self)
                end -- auth succ, go through
            else
                -- auth failed, try next addr
                _add_backup() -- auth may add new backup hosts
                addr = _next_addr()
                if addr == nil then
                    return false, "no more backup host"
                end
                return _connect_once(self, addr)
            end
        end

        return true
    end

    _add_backup()
    return _connect_once(self, {host = self.__host, port = self.__port})
end

local function try_connect(self, once)
    local t = 0
    while not self.__closed do
        local ok, err = connect_once(self)
        if ok then
            if not once then
                log.info("socket: connect to", self.__host, self.__port)
            end
            return
        elseif once then
            return err
        else
            log.warning("socket: connect", err)
        end
        if t > 1000 then
            log.info("socket: try to reconnect", self.__host, self.__port)
            cell.sleep(t)
            t = 0
        else
            cell.sleep(t)
        end
        t = t + 100
    end
end

local function check_connection(self)
    if self.__sock then
        local authco = self.__authcoroutine
        if not authco then
            return true
        end
        if authco == coroutine.running() then
            -- authing
            return true
        end
    end
    if self.__closed then
        return false
    end
end

local function block_connect(self, once)
    local r = check_connection(self)
    if r ~= nil then
        return r
    end
    local err

    if #self.__connecting > 0 then
        -- connecting in other coroutine
        local ev = cell.event()
        table.insert(self.__connecting, ev)
        cell.wait(ev)
    else
        self.__connecting[1] = true
        err = try_connect(self, once)
        for i = 2, #self.__connecting do
            local event = self.__connecting[i]
            self.__connecting[i] = nil
            cell.wakeup(event)
        end
        self.__connecting[1] = nil
    end

    r = check_connection(self)
    if r == nil then
        log.errorf("Connect to %s:%d failed (%s)", self.__host, self.__port, err)
        error("[Error: socket]")
    else
        return r
    end
end

function channel:connect(once)
    self.__closed = false
    return block_connect(self, once)
end

local function wait_for_response(self, response)
    local event = cell.event()
    push_response(self, response, event)
    cell.wait(event)

    local result = self.__result[event]
    self.__result[event] = nil
    local result_data = self.__result_data[event]
    self.__result_data[event] = nil

    if not result then
        error(result_data)
    end

    return result_data
end

function channel:request(request, response)
    assert(block_connect(self, true)) -- connect once

    if not self.__sock:write(request) then
        self.__sock:close()
        wakeup_all(self)
        error("[Error: socket]")
    end

    if response == nil then
        -- no response
        return
    end

    return wait_for_response(self, response)
end

function channel:response(response)
    assert(block_connect(self))

    return wait_for_response(self, response)
end

function channel:close()
    if not self.__closed then
        term_dispatch_thread(self)
        self.__closed = true
        if self.__sock then
            self.__sock:close()
        end
    end
end

function channel:changehost(host, port)
    self.__host = host
    if port then
        self.__port = port
    end
    if not self.__closed and self.__sock then
        self.__sock:close()
    end
end

function channel:changebackup(backup)
    self.__backup = backup
end

channel_meta.__gc = channel.close

return socket_channel
