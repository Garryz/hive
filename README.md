# hive

#### 介绍
**类skynet脚手架**

#### 软件架构
1.  底层 来源于 https://github.com/cloudwu/hive
2.  上层 来源于 https://github.com/cloudwu/skynet
3.  third_party/asio 来源于 https://github.com/chriskohlhoff/asio
4.  third_party/boringssl 来源于 https://github.com/google/boringssl
5.  third_party/jemalloc 来源于 https://github.com/jemalloc/jemalloc
6.  third_party/lfs 来源于 https://github.com/keplerproject/luafilesystem
7.  third_party/lua 来源于 https://github.com/lua/lua
8.  third_party/pb 来源于 https://github.com/starwing/lua-protobuf
9.  third_party/protobuf 来源于 https://github.com/protocolbuffers/protobuf
10. lualib/hotfix 来源于 https://github.com/jinq0123/hotfix
11. lualib/json 来源于 http://dkolf.de/src/dkjson-lua.fsl/home
12. lualib/msgpack 来源于 https://framagit.org/fperrad/lua-MessagePack

#### 安装教程

### linux
1.  gcc g++ 7
2.  third_party/boringssl/BUILDING.md
3.  perl
4.  golang
5.  cmake 3.5
6.  ./build.sh

### mac
1.  third_party/boringssl/BUILDING.md
2.  perl
3.  golang
4.  cmake 3.5
5.  ./build.sh

### windows
1.  Visual Studio 2019
2.  third_party/boringssl/BUILDING.md
3.  perl
4.  nasm
5.  golang
6.  cmake 3.5
7.  ./build.bat

#### 使用说明

1.  ./lua ./main.lua ./test/config_main
2.  ./lua ./main.lua ./test/config_main1
3.  ./lua ./main.lua ./test/config_debug_console
4.  ./lua ./main.lua ./test/config_http
5.  ./lua ./main.lua ./test/config_mysql
6.  ./lua ./main.lua ./test/cluster/config_cluster1 ./lua ./main.lua ./test/cluster/config_cluster2
7.  ./lua ./main.lua ./test/datasheet/config
8.  ./lua ./main.lua ./test/redis/config_redis
9.  ./lua ./main.lua ./test/redis/config_redis2
10. ./lua ./main.lua ./test/redis/config_pipeline

#### 参与贡献

#### 特技
