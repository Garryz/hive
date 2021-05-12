local cell = require "cell"

local command = {}
local message = {}

function command.add(a, b)
    return a + b
end

function message.print(str)
    print("cluster_service", str)
end

cell.command(command)
cell.message(message)
