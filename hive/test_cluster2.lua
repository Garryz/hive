local hive = require "hive"

hive.start {
    thread = 4,
    main = "test.cluster.cluster_main2"
}

print("lua exit")
