local socket = require "socket"
local cell = require "cell"

local setmetatable = setmetatable
local error = error

local sockethelper = {}
local socket_error =
    setmetatable(
    {},
    {
        __tostring = function()
            return "[Socket Error]"
        end
    }
)

sockethelper.socket_error = socket_error

local function preread(sock, str)
    return function(sz)
        if str then
            if sz == #str or sz == nil then
                local ret = str
                str = nil
                return ret
            else
                if sz < #str then
                    local ret = str:sub(1, sz)
                    str = str:sub(sz + 1)
                    return ret
                else
                    sz = sz - #str
                    local ret = sock:readbytes(sz)
                    if ret then
                        ret = str .. ret
                        str = nil
                        return ret
                    else
                        error(socket_error)
                    end
                end
            end
        else
            local ret = sock:readbytes(sz)
            if ret then
                return ret
            else
                error(socket_error)
            end
        end
    end
end

function sockethelper.readfunc(sock, pre)
    if pre then
        return preread(sock, pre)
    end
    return function(sz)
        local ret = sock:readbytes(sz)
        if ret then
            return ret
        else
            error(socket_error)
        end
    end
end

function sockethelper.readall(sock)
    return sock:readall()
end

function sockethelper.writefunc(sock)
    return function(content)
        local ok = sock:write(content)
        if not ok then
            error(socket_error)
        end
    end
end

function sockethelper.connect(host, port, timeout)
    local sock
    if timeout then
        sock = cell.execwithtimeout(timeout, socket.connect, host, port)
    else
        sock = socket.connect(host, port)
    end
    if sock then
        return sock
    end
    error(socket_error)
end

function sockethelper.close(sock)
    sock:disconnect()
end

return sockethelper
