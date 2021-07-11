local cell = require "cell"
local redis = require "db.redis"

local db

local function add1(key, count)
    local t = {}
    for i = 1, count do
        t[2 * i - 1] = "key" .. i
        t[2 * i] = "value" .. i
    end
    db:hmset(key, table.unpack(t))
end

local function add2(key, count)
    local t = {}
    for i = 1, count do
        t[2 * i - 1] = "key" .. i
        t[2 * i] = "value" .. i
    end
    table.insert(t, 1, key)
    db:hmset(t)
end

function cell.main()
    db = redis.connect {host = "192.168.1.6", port = 6379, db = 0, auth = "123456"}
    print("dbsize:", db:dbsize())
    local ok, msg = xpcall(add1, debug.traceback, "test1", 250000)
    if not ok then
        print("add1 failed", msg)
    else
        print("add1 succed")
    end

    ok, msg = xpcall(add2, debug.traceback, "test2", 250000)
    if not ok then
        print("add2 failed", msg)
    else
        print("add2 succed")
    end
    print("dbsize:", db:dbsize())

    print("redistest launched")
end
