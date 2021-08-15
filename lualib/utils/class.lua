function Class(classname, super)
    local class_type = {}
    class_type.__cname = classname
    class_type.ctor = false
    if super then
        class_type.super = super
        setmetatable(class_type, {__index = super})
    end

    function class_type.new(...)
        local obj = setmetatable({}, {__index = class_type})
        class_type.ctor(obj, ...)
        return obj
    end

    return class_type
end
