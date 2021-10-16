local cell = require "cell"
local cluster = require "cluster"

function cell.main()
    print(cluster.call("cluster1", "cluster_service", "add", 1, 2))
    cluster.send("cluster1", "cluster_service", "print", "测试cluster", "测试cluster2")
    local id = cluster.query("cluster1", "cluster_service")
    print(cluster.call("cluster1", id, "add", 3, 4))
end
