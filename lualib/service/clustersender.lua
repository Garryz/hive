local cell = require "cell"
local sc = require "socketchannel"
local mp = require "msgpack"
local log = require "log"

local string = string
local table = table
local pcall = pcall
local error = error

local command = {}
local message = {}

local channel

local function pack(service, session, func, ...)
    local request = {}
    request[2] = mp.pack({service = service, session = session, func = func, args = table.pack(...)})
    request[1] = string.pack("<I4", #request[2])
    return table.concat(request)
end

local function send_request(service, func, ...)
    local session = cell.event()
    return channel:request(pack(service, session, func, ...), session)
end

function command.req(service, func, ...)
    local ok, msg = pcall(send_request, service, func, ...)
    if ok then
        return table.unpack(msg)
    else
        error(msg)
    end
end

function command.changenode(host, port)
    if not host then
        log.errorf("Close cluster sender %s:%d", channel.__host, channel.__port)
        channel:close()
    else
        channel:changehost(host, tonumber(port))
        channel:connect(true)
    end
end

function message.push(service, func, ...)
    channel:request(pack(service, nil, func, ...))
end

cell.command(command)
cell.message(message)

local function read_response(sock)
    local sz = string.unpack("<I4", sock:readbytes(4))
    local msg = sock:readbytes(sz)
    local response = mp.unpack(msg)
    return response.session, response.ok, response.data -- session, ok, data
end

function cell.main(init_host, init_port)
    channel =
        sc.channel {
        host = init_host,
        port = tonumber(init_port),
        response = read_response
    }
end
