local cell = require "cell"
local datasheet = require "datasheet"
local builder = require "datasheet.builder"
local env = require "env"

local function dump(t, prefix)
    for k, v in pairs(t) do
        print(prefix, k, v)
        if type(v) == "table" then
            dump(v, prefix .. "." .. k)
        end
    end
end

function cell.main(mode)
    print(env.getconfig("cpath"))
    if mode == "child" then
        local t = datasheet.query("foobar")
        dump(t, "[CHILD]")
        cell.sleep(100)
        cell.exit()
    else
        builder.new("foobar", {a = 1, b = 2, c = {3}})
        local t = datasheet.query "foobar"
        local c = t.c
        dump(t, "[1]")
        builder.update("foobar", {b = 4})
        print("sleep")
        cell.sleep(100)
        dump(t, "[2]")
        dump(c, "[2.c]")
        builder.update("foobar", {a = 6, c = 7, d = 8})
        print("sleep")
        cell.sleep(100)
        dump(t, "[3]")
    end
end
