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

function cell.main()
    for i = 1, 50 do
        cell.fork(
            function()
                local sock = socket.connect("127.0.0.1", 8888)
                print("connect", sock.__fd)
                local str = random_str(1024)
                sock:write(str .. "\n")
                local line = sock:readline("\n")
                while line do
                    str = random_str(1024)
                    sock:write(str .. "\n")
                    line = sock:readline("\n")
                end
            end
        )
    end
end
