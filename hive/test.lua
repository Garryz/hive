local hive = require "hive"

hive.start {
    thread = 4,
    main = "test.redis.pipeline"
    -- main = "test.main"
}

print("lua exit")
