local cell = require "cell"
local csocket = require "cell.c.socket"

local coroutine = coroutine
local assert = assert
local type = type

local BUFFER_LIMIT = 128 * 1024

local sockets_fd = nil
local sockets_accept = {}
local sockets_closed = {}
local sockets_event = {}
local sockets_arg = {}
local sockets_buffer = {}
local sockets_pause = {}
local sockets_warning = {}
local sockets_onclose = {}
local sockets = {}

local socket = {}
local listen_socket = {}

local socket_ins = {}

local function close_msg(self)
    cell.send(sockets_fd, "disconnect", self.__fd)
end

local socket_meta = {
    __index = socket,
    __gc = close_msg,
    __tostring = function(self)
        return "[socket: " .. self.__fd .. "]"
    end
}

local listen_meta = {
    __index = listen_socket,
    __gc = close_msg,
    __tostring = function(self)
        return "[socket listen: " .. self.__fd .. "]"
    end
}

function socket:write(msg)
    local fd = self.__fd
    if sockets_closed[fd] then
        return
    end
    return cell.rawsend(sockets_fd, 10, fd, csocket.sendpack(msg))
end

function socket:disconnect()
    assert(sockets_fd)
    local fd = self.__fd
    sockets[fd] = nil
    sockets_closed[fd] = true

    if sockets_event[fd] then
        cell.wakeup(sockets_event[fd])
        sockets_event[fd] = nil
    else
        sockets_buffer[fd] = nil
    end

    cell.send(sockets_fd, "disconnect", fd)

    local cb = sockets_onclose[fd]
    if cb then
        cb(fd)
        sockets_onclose[fd] = nil
    end
end

function socket:warning(callback)
    sockets_warning[self.__fd] = callback
end

function socket:onclose(callback)
    sockets_onclose[self.__fd] = callback
end

local function socket_pause(fd, size)
    if sockets_pause[fd] then
        return
    end
    if size then
        print(string.format("Pause socket (%d) size: %d", fd, size))
    else
        print(string.format("Pause socket (%d)", fd))
    end
    cell.send(sockets_fd, "pause", fd)
    sockets_pause[fd] = true
end

local function socket_wait(fd, sep)
    assert(sockets_event[fd] == nil)
    sockets_event[fd] = cell.event()
    sockets_arg[fd] = sep
    if sockets_pause[fd] then
        print(string.format("Resume socket (%d)", fd))
        cell.send(sockets_fd, "resume", fd)
        cell.wait(sockets_event[fd])
        sockets_pause[fd] = nil
    else
        cell.wait(sockets_event[fd])
    end
end

function socket:readbytes(bytes)
    local fd = self.__fd
    if bytes == nil then
        if not sockets_closed[fd] then
            if sockets_buffer[fd] then
                -- read some bytes
                local data = csocket.readall(sockets_buffer[fd])
                if data ~= "" then
                    return data
                end
            end
            socket_wait(fd, 0)
        end
        if sockets_buffer[fd] then
            local data = csocket.readall(sockets_buffer[fd])
            if sockets_closed[fd] then
                sockets_buffer[fd] = nil
            end
            return data ~= "" and data
        end
        return
    end

    if not sockets_closed[fd] then
        if sockets_buffer[fd] then
            local data = csocket.pop(sockets_buffer[fd], bytes)
            if data then
                return data
            end
        end
        socket_wait(fd, bytes)
    end
    if sockets_buffer[fd] then
        local data = csocket.pop(sockets_buffer[fd], bytes)
        if sockets_closed[fd] then
            sockets_buffer[fd] = nil
        end
        return data
    end
end

function socket:readline(sep)
    local fd = self.__fd
    sep = sep or "\n"
    if not sockets_closed[fd] then
        if sockets_buffer[fd] then
            local line = csocket.readline(sockets_buffer[fd], sep)
            if line then
                return line
            end
        end
        socket_wait(fd, sep)
    end
    if sockets_buffer[fd] then
        local line = csocket.readline(sockets_buffer[fd], sep)
        if line then
            if sockets_closed[fd] then
                sockets_buffer[fd] = nil
            end
            return line
        end
        if sockets_closed[fd] then
            line = csocket.readall(sockets_buffer[fd])
            sockets_buffer[fd] = nil
            return line ~= "" and line
        end
    end
end

function socket:readall()
    local fd = self.__fd
    if not sockets_closed[fd] then
        socket_wait(fd, true)
    end
    local r = ""
    if sockets_buffer[fd] then
        r = csocket.readall(sockets_buffer[fd])
        sockets_buffer[fd] = nil
    end
    return r
end

function listen_socket:disconnect()
    sockets_accept[self.__fd] = nil
    socket.disconnect(self)
end

function socket_ins.listen(addr, port, accepter)
    assert(type(accepter) == "function")
    sockets_fd = sockets_fd or cell.cmd("socket")
    local obj = {__fd = assert(cell.call(sockets_fd, "listen", cell.self, addr, port), "Listen failed")}
    sockets_accept[obj.__fd] = function(fd, addr)
        return accepter(fd, addr, obj)
    end
    setmetatable(obj, listen_meta)
    sockets[obj.__fd] = obj
    return obj
end

function socket_ins.connect(addr, port)
    sockets_fd = sockets_fd or cell.cmd("socket")
    local ev = cell.event()
    local fd, err = cell.rawcall(sockets_fd, ev, 3, "connect", cell.self, addr, port, ev)
    if not fd then
        return fd, err
    end
    local obj = {__fd = fd}
    setmetatable(obj, socket_meta)
    sockets[obj.__fd] = obj
    return obj
end

function socket_ins.bind(fd)
    sockets_fd = sockets_fd or cell.cmd("socket")
    local obj = {__fd = fd}
    setmetatable(obj, socket_meta)
    sockets[obj.__fd] = obj
    return obj
end

cell.dispatch {
    msg_type = 6, -- new socket
    dispatch = function(accept_fd, fd, addr)
        local accepter = sockets_accept[accept_fd]
        if accepter then
            -- accepter: new fd ,  ip addr
            local co =
                cell.co_create(
                function()
                    local forward = accepter(fd, addr) or cell.self
                    cell.call(sockets_fd, "forward", fd, forward)
                    return "EXIT"
                end
            )
            cell.suspend(nil, nil, co, coroutine.resume(co))
        end
    end
}

cell.dispatch {
    msg_type = 7, -- socket message
    dispatch = function(fd, msg)
        local buffer, bsz = csocket.push(sockets_buffer[fd], msg)
        if sockets_closed[fd] then
            sockets_buffer[fd] = nil
        else
            sockets_buffer[fd] = buffer
        end
        local ev = sockets_event[fd]
        if not ev then
            return
        end
        if sockets_closed[fd] then
            cell.wakeup(ev)
            sockets_event[fd] = nil
        else
            local arg = sockets_arg[fd]
            if type(arg) == "string" then
                if csocket.readline(buffer, arg, true) then
                    if bsz > BUFFER_LIMIT then
                        socket_pause(fd, bsz)
                    end
                    cell.wakeup(ev)
                    sockets_event[fd] = nil
                end
            elseif type(arg) == "number" then
                if bsz >= arg then
                    if bsz > BUFFER_LIMIT then
                        socket_pause(fd, bsz)
                    end
                    cell.wakeup(ev)
                    sockets_event[fd] = nil
                end
            elseif bsz > BUFFER_LIMIT and not sockets_pause[fd] then
                socket_pause(fd, bsz)
            end
        end
    end
}

cell.dispatch {
    msg_type = 8, -- close socket
    dispatch = function(fd)
        local obj = sockets[fd]
        if obj then
            obj:disconnect()
        end
    end
}

cell.dispatch {
    msg_type = 9, -- write buffer warning
    dispatch = function(fd, size)
        local obj = sockets[fd]
        if obj then
            local warning = sockets_warning[fd] or function(fd, size)
                    print(string.format("WARNING: %d K bytes need to send out (fd = %d)", size, fd))
                end
            warning(fd, size)
        end
    end
}

return socket_ins
