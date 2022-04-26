local ffi = require "ffi"
ffi.cdef "char* strcpy(char* d, const char* s)"

local ffi_new, strcpy = ffi.new, ffi.C.strcpy


return {
    new = function (buflen)
        return setmetatable({}, {
            __newindex = function (self, key, source)
                if source then
                    local dest = ffi_new("char[?]", buflen)
                    strcpy(dest, source)
                    rawset(self, key, dest)
                else
                    rawset(self, key, nil)
                end
            end
        })
    end
}
