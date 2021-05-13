local cell = require "cell"

local command = {}
local message = {}

function command.add(a, b)
    return a + b
end

function message.print(...)
    print("cluster_service", ...)
end

cell.command(command)
cell.message(message)
