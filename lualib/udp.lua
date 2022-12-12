local cell = require "cell"
local csocket = require "cell.c.socket"
local log = require "log"

local coroutine = coroutine
local assert = assert
local type = type
local setmetatable = setmetatable

local UDP_LIMIT = 1400

local sockets_fd = nil
local sockets_accept = {}
local sockets_closed = {}
local sockets_event = {}
local sockets_buffer = {}
local sockets_onclose = {}
local sockets = {}

local socket = {}

local listen_socket = {}

local socket_ins = {}

local function close_msg(self)
    cell.send(sockets_fd, "udp_disconnect", self.__fd)
end

local socket_meta = {
    __index = socket,
    __gc = close_msg,
    __tostring = function(self)
        return "[udp: " .. self.__fd .. "]"
    end
}

local listen_meta = {
    __index = listen_socket,
    __gc = close_msg,
    __tostring = function(self)
        return "[udp listen: " .. self.__fd .. "]"
    end
}

function socket:fd()
    return self.__fd
end

function socket:addr()
    return self.__addr
end

function socket:write(msg)
    assert(#msg <= UDP_LIMIT, "Over Udp Limit")
    local fd = self.__fd
    if sockets_closed[fd] then
        return
    end
    return cell.rawsend(sockets_fd, 15, fd, csocket.sendpack(msg))
end

function socket:disconnect()
    assert(sockets_fd)
    local fd = self.__fd
    sockets[fd] = nil
    sockets_closed[fd] = true

    if sockets_event[fd] then
        cell.wakeup(sockets_event[fd])
        sockets_event[fd] = nil
    end

    cell.send(sockets_fd, "udp_disconnect", self.__fd)

    local cb = sockets_onclose[fd]
    if cb then
        cb(fd)
        sockets_onclose[fd] = nil
    end
end

function socket:onclose(callback)
    sockets_onclose[self.__fd] = callback
end

local function socket_wait(fd)
    assert(sockets_event[fd] == nil)
    sockets_event[fd] = cell.event()
    cell.wait(sockets_event[fd])
end

function socket:read()
    local fd = self.__fd

    if not sockets_closed[fd] then
        if sockets_buffer[fd] then
            local data = csocket.udp_pop(sockets_buffer[fd])
            if data then
                return data
            end
        end
        socket_wait(fd)
    end

    if sockets_buffer[fd] then
        local data = csocket.udp_pop(sockets_buffer[fd])
        if sockets_closed[fd] then
            sockets_buffer[fd] = nil
        end
        return data
    end
end

function listen_socket:disconnect()
    sockets_accept[self.__fd] = nil
    socket.disconnect(self)
end

function socket_ins.listen(addr, port, accepter)
    assert(type(accepter) == "function")
    sockets_fd = sockets_fd or cell.cmd("socket")
    local obj = {
        __fd = assert(cell.call(sockets_fd, "udp_listen", cell.self, addr, port), "Udp listen failed"),
        __addr = addr
    }
    sockets_accept[obj.__fd] = function(fd, addr)
        local c = accepter(fd, addr, obj)
        if c and type(c) ~= "userdata" then
            c = cell.cmd("getcell", c)
        end
        return c
    end
    setmetatable(obj, listen_meta)
    sockets[obj.__fd] = obj
    return obj
end

function socket_ins.connect(addr, port)
    sockets_fd = sockets_fd or cell.cmd("socket")
    local ev = cell.event()
    local fd, err = cell.rawcall(sockets_fd, ev, 3, "udp_connect", cell.self, addr, port, ev)
    if not fd then
        return fd, err
    end
    local obj = {
        __fd = fd,
        __addr = addr
    }
    setmetatable(obj, socket_meta)
    sockets[obj.__fd] = obj
    return obj
end

function socket_ins.bind(fd, addr)
    sockets_fd = sockets_fd or cell.cmd("socket")
    local obj = {
        __fd = fd,
        __addr = addr
    }
    setmetatable(obj, socket_meta)
    sockets[obj.__fd] = obj
    return obj
end

cell.dispatch {
    msg_type = 12, -- new udp socket 
    dispatch = function(accept_fd, fd, addr)
        local accepter = sockets_accept[accept_fd]
        if accepter then
            -- accepter: new fd, ip addr
            local co = cell.cocreate(function()
                local forward = accepter(fd, addr) or cell.self
                cell.call(sockets_fd, "udp_forward", fd, forward)
                return "EXIT"
            end)
            cell.suspend(nil, nil, co, coroutine.resume(co))
        end
    end
}

cell.dispatch {
    msg_type = 13, -- udp socket message
    dispatch = function(fd, msg)
        local buffer, hasmsg = csocket.udp_push(sockets_buffer[fd], msg)
        if sockets_closed[fd] then
            sockets_buffer[fd] = nil
        else
            sockets_buffer[fd] = buffer
        end
        local ev = sockets_event[fd]
        if not ev then
            return
        end
        if sockets_closed[fd] or hasmsg then
            cell.wakeup(ev)
            sockets_event[fd] = nil
        end
    end
}

cell.dispatch {
    msg_type = 14, -- udp close socket
    dispatch = function(fd)
        local obj = sockets[fd]
        if obj then
            local co = cell.cocreate(function()
                obj:disconnect()
                return "EXIT"
            end)
            cell.suspend(nil, nil, co, coroutine.resume(co))
        end
    end
}

return socket_ins
