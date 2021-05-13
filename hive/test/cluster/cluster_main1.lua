local cell = require "cell"
local cluster = require "cluster"

function cell.main()
    local service = cell.newservice("test.cluster.cluster_service")
    cluster.register("cluster_service", service)
    cluster.open("cluster1")
end
