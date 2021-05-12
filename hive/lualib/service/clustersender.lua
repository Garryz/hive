local cell = require "cell"
local sc = require "socketchannel"
local mp = require "msgpack"

local string = string
local table = table
local pcall = pcall
local error = error

local command = {}

local channel

local function pack(service, session, func, ...)
    local request = {}
    request[2] = mp.pack({service = service, session = session, func = func, args = {...}})
    request[1] = string.pack("<I4", #request[2])
    return table.concat(request)
end

local function send_request(service, func, ...)
    local session = cell.event()
    return channel.request(pack(service, session, func, ...), session)
end

function command.req(service, func, ...)
    local ok, msg = pcall(send_request, service, func, ...)
    if ok then
        if type(msg) == "table" then
            return table.unpack(msg)
        else
            return msg
        end
    else
        error(msg)
    end
end

function command.push(service, func, ...)
    channel:request(pack(service, nil, func, ...))
end

function command.changenode(host, port)
    channel:changehost(host, tonumber(port))
    channel:connect(true)
end

cell.command(command)

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
        prot = tonumber(init_port),
        response = read_response
    }
end
