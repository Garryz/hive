local cell = require "cell"
local cluster = require "cluster"

function cell.main()
    print(cluster.call("cluster1", "cluster_service", "add", 1, 2))
    cluster.send("cluster1", "cluster_service", "print", "测试cluster")
end
