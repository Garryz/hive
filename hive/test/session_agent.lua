local cell = require "cell"
local socket = require "socket"

local function random_str(len)
    math.randomseed(os.time())
    local len = math.random(0, len)
    local rand_table = {}
    for i = 1, len do
        local rand_num = math.random(1, 3)
        if rand_num == 1 then
            rand_num = string.char(math.random(0, 25) + 65)
        elseif rand_num == 2 then
            rand_num = string.char(math.random(0, 25) + 97)
        else
            rand_num = math.random(0, 9)
        end
        table.insert(rand_table, rand_num)
    end
    return table.concat(rand_table)
end

local message = {}

function message.forward(fd, addr, listen_fd)
    cell.fork(
        function()
            local obj = socket.bind(fd)
            local str
            local line = obj:readline("\n")
            while line do
                str = random_str(1024)
                obj:write(str .. "\n")
                line = obj:readline("\n")
            end
        end
    )
end

cell.message(message)
