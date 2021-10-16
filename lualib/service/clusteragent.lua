local cell = require "cell"
local socket = require "socket"
local mp = require "msgpack"

local table = table
local rawget = rawget
local ipairs = ipairs
local setmetatable = setmetatable
local string = string
local type = type

local message = {}

local clusterd

local register_name

local sock

local inquery_name = {}

local register_name_mt = {
    __index = function(self, name)
        local waitevent = inquery_name[name]
        if waitevent then
            local event = cell.event()
            table.insert(waitevent, event)
            cell.wait(event)
            return rawget(self, name)
        else
            waitevent = {}
            inquery_name[name] = waitevent
            local service = cell.call(clusterd, "queryname", name)
            if service then
                self[name] = service
            end
            inquery_name[name] = nil
            for _, event in ipairs(waitevent) do
                cell.wakeup(event)
            end
            return service
        end
    end
}

local function new_register_name()
    return setmetatable({}, register_name_mt)
end

function message.namechange()
    register_name = new_register_name()
end

cell.message(message)

local function pack(session, ok, data)
    local response = {}
    response[2] = mp.pack({session = session, ok = ok, data = data})
    response[1] = string.pack("<I4", #response[2])
    return table.concat(response)
end

local function dispatch_request()
    local sz = sock:readbytes(4)
    while sz do
        sz = string.unpack("<I4", sz)
        local msg = sock:readbytes(sz)
        if msg == nil then
            sock:disconnect()
            return
        end
        local request = mp.unpack(msg)
        if request == nil or request.service == nil then
            sock:disconnect()
            return
        end
        if request.func and type(request.func) == "string" and request.func ~= "" then
            local service
            if type(request.service) == "string" then
                service = register_name[request.service]
            else
                service = cell.cmd("getcell", request.service)
            end
            if request.session then
                local ok, data = false, "service not found"
                if service then
                    ok, data =
                        pcall(
                        function()
                            if request.args then
                                return table.pack(cell.call(service, request.func, table.unpack(request.args)))
                            else
                                return table.pack(cell.call(service, request.func))
                            end
                        end
                    )
                end
                sock:write(pack(request.session, ok, data))
            elseif service then
                if request.args then
                    cell.send(service, request.func, table.unpack(request.args))
                else
                    cell.send(service, request.func)
                end
            end
        else
            local id
            local service = register_name[request.service]
            if service then
                id = service:id()
            end
            sock:write(pack(request.session, true, {id}))
        end
        sz = sock:readbytes(4)
    end
    sock:disconnect()
end

function cell.main(fd)
    clusterd = cell.uniqueservice("service.clusterd")
    register_name = new_register_name()
    sock = socket.bind(fd)
    sock:onclose(
        function(fd)
            cell.call(clusterd, "closeagent", fd)
            cell.exit()
        end
    )
    cell.fork(dispatch_request)
end
