local hive = require "hive"

hive.start {
    thread = 4,
    main = "test.cluster.cluster_main1"
}

print("lua exit")
