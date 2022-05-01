local ffi = require "ffi" --[[../../luajit/src/lib_ffi.c]]
local new, copy, sizeof = ffi.new, ffi.copy, ffi.sizeof

return { -- XXX NOTE: does not typecheck, will implicitly cast new values XXX --
    new = function (_type, length)
        if length then return setmetatable({}, {
            __newindex = function (self, key, source)
                if source then
                    local dest = new(_type, length)
                    copy(dest, source, length)
                    rawset(self, key, dest)
                else
                    rawset(self, key, nil)
                end
            end;
            __index = function (self, key)
                local dest = new(_type, length)
                return rawset(self, key, dest) and dest
            end
        })
        else return setmetatable({}, {
            __newindex = function (self, key, source)
                if source then
                    local dest = new(_type)
                    copy(dest, source, sizeof(_type))
                    rawset(self, key, dest)
                else
                    rawset(self, key, nil)
                end
            end;
            __index = function (self, key)
                local dest = new(_type)
                return rawset(self, key, dest) and dest
            end
        })
        end
    end
}
