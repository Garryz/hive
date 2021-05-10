--[[
Author: your name
Date: 2021-05-06 14:04:26
LastEditTime: 2021-05-07 15:35:29
LastEditors: Please set LastEditors
Description: In User Settings Edit
FilePath: /hive/hive/test/session.lua
--]]
local cell = require "cell"
local socket = require "socket"

local sessions = {}

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

function cell.main(fd, addr)
    print(addr, "connected")
    print("cell addr", cell.self)
    local obj = socket.bind(fd)
    cell.fork(
        function()
            -- local line = obj:readline "\n"
            -- print("client read", line)
            -- obj:write(line .. "\n")
            -- obj:disconnect()
            -- cell.exit()

            -- local line = obj:readall()
            -- print("client read", line)

            -- local line = obj:readbytes()
            -- print("client read", line)

            local line = obj:readline("\n")
            print("client read 1", line)
            line = obj:readline("\n")
            print("client read 2", line)
        end
    )

    -- local obj = socket.bind(fd)
    -- sessions[fd] = obj
    -- cell.fork(
    --     function()
    --         local str
    --         local line = obj:readline("\n")
    --         while line do
    --             -- print(obj.__fd, "read", line)
    --             str = random_str(1024)
    --             obj:write(str .. "\n")
    --             -- print(obj.__fd, "write", str)
    --             line = obj:readline("\n")
    --         end
    --     end
    -- )
end
