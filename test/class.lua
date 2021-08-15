package.path = "./lualib/?.lua;./lualib/?/init.lua;" .. package.path

require "utils.class"

local base_type = Class("base_type")

function base_type:ctor(x)
    print("base_type ctor")
    self.x = x
end

function base_type:print_x()
    print(self.x)
end

function base_type:hello()
    print("hello base_type")
end

local test = Class("test", base_type)

function test:ctor(x)
    test.super.ctor(self, x)
    print("test ctor")
end

function test:hello()
    print("hello test")
end

local a = test.new(1)
a:print_x()
a:hello()
