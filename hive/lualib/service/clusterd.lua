local cell = require "cell"

local command = {}

local node_address = {}
local node_sender = {}

local connecting = {}

local function open_channel(t, key)
    local ct = connecting[key]
    if ct then
        local event = cell.event()
        table.insert(ct, event)
        cell.wait(event)
        return assert(ct.channel)
    end
    ct = {}
    connecting[key] = ct
    local address = node_address[key]
    local succ, err, c
    if address then
        local host, port = string.match(address, "([^:]+):(.*)$")
        c = node_sender[key]
        if c == nil then
            c = cell.newservice("clustersender", key, host, port)
            if node_sender[key] then
                -- doublc check
                cell.kill(c)
                c = node_sender[key]
            else
                node_sender[key] = c
            end
        end

        succ = pcall(cell.call, c, "changenode", host, port)

        if succ then
            t[key] = c
            ct.channel = c
        else
            err = string.format("changenode [%s] (%s:%s) failed", key, host, port)
        end
    else
        err = string.format("cluster node [%s] is %s.", key, address == false and "down" or "absent")
    end
    connecting[key] = nil
    for _, event in ipairs(ct) do
        cell.wakeup(event)
    end
    if node_address[key] ~= address then
        return open_channel(t, key)
    end
    assert(succ, err)
    return c
end

local node_channel = setmetatable({}, {__index = open_channel})

function command.sender(node)
    return node_channel[node]
end

cell.command(command)

function cell.main()
end
