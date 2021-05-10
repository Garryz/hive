#!/bin/sh

rm -rf build hive/luaclib/* hive/core* hive/lua hive/lua.exe hive/lua.ilk hive/lua.pdb hive/luac hive/luac.exe hive/luac.ilk hive/luac.pdb

mkdir build

cd build

cmake ..

cmake --build . --config Debug --target all --clean-first