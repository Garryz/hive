#!/bin/sh

rm -rf build hive/luaclib/* hive/core* hive/lua hive/lua.* hive/luac hive/luac.* hive/protoc*

mkdir build

cd build

cmake ..

cmake --build . --config Release --target all --clean-first
