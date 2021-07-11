#!/bin/sh

rm -rf build luaclib/* core* lua lua.* luac luac.* protoc*

mkdir build

cd build

cmake ..

cmake --build . --config Release --target all --clean-first
