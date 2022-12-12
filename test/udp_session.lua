local cell = require "cell"
local udp = require "udp"

local sessions = {}

local function random_str(len)
    math.randomseed(os.time())
    local len = math.random(1, len)
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

function cell.main(fd, addr)
    print(addr, "connected")
    print("cell addr", cell.self)

    local obj = udp.bind(fd)
    sessions[fd] = obj
    cell.fork(function()
        local str
        local line = obj:read()
        while line do
            print(obj.__fd, "read", line)
            str = random_str(10)
            obj:write(str .. "\r\n")
            print(obj.__fd, "write", str)
            line = obj:read()
        end
    end)
end
