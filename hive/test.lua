local hive = require "hive"

hive.start {
    thread = 4,
    main = "test.main"
}

print("lua exit")
