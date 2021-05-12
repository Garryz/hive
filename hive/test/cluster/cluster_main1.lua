local cell = require "cell"

function cell.main()
    local service = cell.newservice("test.cluster.cluster_service")
    local cluster = require "cluster"
    cluster.register("cluster_service", service)
    cluster.open("cluster1")
end
