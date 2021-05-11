local cell = require "cell"

local command = {}

local node_address = {}

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
end

local node_channel = setmetatable({}, {__index = open_channel})

function command.sender(node)
    return node_channel[node]
end

cell.command(command)

function cell.main()
end
