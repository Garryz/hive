local cell = require "cell"

local pcall = pcall
local print = print
local ipairs = ipairs
local type = type
local setmetatable = setmetatable
local table = table
local assert = assert

local clusterd = cell.uniqueservice("service.clusterd")

local cluster = {}

local sender = {}
local task_queue = {}

local function request_sender(q, node)
    local ok, c = pcall(cell.call, clusterd, "sender", node)
    if not ok then
        print(c)
        c = nil
    end
    -- run tasks in queue
    local confirm = cell.event()
    q.confirm = confirm
    q.sender = c
    for _, task in ipairs(q) do
        if type(task) == "table" then
            if c then
                cell.send(c, "push", table.unpack(task))
            end
        else
            cell.wakeup(task)
            cell.wait(confirm)
        end
    end
    task_queue[node] = nil
    sender[node] = c
end

local function get_queue(t, node)
    local q = {}
    t[node] = q
    cell.fork(request_sender, q, node)
end

setmetatable(task_queue, {__index = get_queue})

local function get_sender(node)
    local s = sender[node]
    if not s then
        local q = task_queue[node]
        local task = cell.event()
        table.insert(q, task)
        cell.wait(task)
        cell.wakeup(q.confirm)
        return q.sender
    end
    return s
end

function cluster.call(node, service, func, ...)
    assert(type(node) == "string")
    assert(type(service) == "string")
    return cell.call(get_sender(node), "req", service, func, ...)
end

function cluster.send(node, service, func, ...)
    assert(type(node) == "string")
    assert(type[service] == "string")
    -- push is the same with req, but no response
    local s = sender[node]
    if not s then
        table.insert(task_queue[node], table.pack(service, func, ...))
    else
        cell.send(sender[node], "push", service, func, ...)
    end
end

function cluster.open(port)
    if type(port) == "string" then
        cell.call(clusterd, "listen", port)
    else
        cell.call(clusterd, "listen", "0.0.0.0", port)
    end
end

function cluster.reload(config)
    cell.call(clusterd, "reload", config)
end

function cluster.register(name, service)
    assert(type(name) == "string")
    assert(type(service) == "userdata")
    return cell.call(clusterd, "register", name, service)
end

return cluster
