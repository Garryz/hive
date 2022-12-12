local cell = require "cell"
local csocket = require "cell.c.socket"

local command = {}
local message = {}

function command.listen(source, addr, port)
    return csocket.listen(source, addr, port)
end

function command.forward(fd, addr)
    return csocket.forward(fd, addr)
end

function message.connect(source, addr, port, ev)
    csocket.connect(source, addr, port, ev)
end

function message.pause(fd)
    csocket.pause(fd)
end

function message.resume(fd)
    csocket.resume(fd)
end

function message.disconnect(fd)
    csocket.close(fd)
end

function command.udp_listen(source, addr, port)
    return csocket.udp_listen(source, addr, port)
end

function command.udp_forward(fd, addr)
    return csocket.udp_forward(fd, addr)
end

function message.udp_connect(source, addr, port, ev)
    csocket.udp_connect(source, addr, port, ev)
end

function message.udp_disconnect(fd)
    csocket.udp_close(fd)
end

cell.command(command)
cell.message(message)

cell.dispatch {
    msg_type = 10, -- write socket
    dispatch = function(...)
        csocket.send(...)
        csocket.pollonce()
    end
}

cell.dispatch {
    msg_type = 15, -- udp write socket
    dispatch = function(...)
        csocket.udp_send(...)
        csocket.pollonce()
    end
}

local dispatch_message = cell.getdispatch(3)
cell.dispatch {
    msg_type = 3, -- message
    dispatch = function(...)
        dispatch_message(...)
        csocket.pollonce()
    end
}

local dispatch_command = cell.getdispatch(2)
cell.dispatch {
    msg_type = 2, -- command
    dispatch = function(...)
        dispatch_command(...)
        csocket.pollonce()
    end
}

function cell.main()
    while true do
        csocket.pollfor(100) -- milliseconds
        cell.yield()
    end
end
