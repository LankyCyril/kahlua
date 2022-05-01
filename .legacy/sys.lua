local sys = {}
-- `loadglobal` and `loadffi` may serve no purpose. However, I've seen strange
-- segfaults that were resolved by loading something "once" to the same _G[key]
-- instead of locally requiring in multiple times -- needs testing.


sys.loadglobal = function (libname)
    -- Load LuaJIT library `libname` into a new global environment slot --
    local gname = random_global_name(libname)
    if _G[gname] then
        if (_G[gname].C == nil) or (type(_G[gname].C) ~= "userdata") then
            error("kahlua.sys.loadglobal: random global name taken")
        end
    end
    _G[gname] = require(libname)
    return _G[gname]
end


sys.loadffi = function (libname, dealiased, tester, cdefs)
    -- Load and add `libname` to the global environment --
    local ffi = sys.loadglobal "ffi" -- <../../luajit/src/lib_ffi.c>
    local gname = random_global_name(libname)
    local error_mask = "kahlua.sys.loadffi: %s"
    if _G[gname] then
        if type(_G[gname]) ~= "userdata" then
            error("kahlua.sys.loadffi: random global name taken by an object")
        elseif tester then
            if pcall(function () local _ = _G[gname][tester] end) ~= true then
                error(error_mask:format(
                    "random global name taken by some userdata"
                ))
            end
        end
    end
    dealiased = dealiased or libname:gsub("lib$", "")
    if dealiased then
        local status
        status, _G[gname] = pcall(ffi.load, dealiased)
        if status ~= true then
            error(error_mask:format("could not load " .. libname))
        end
        ffi.cdef(cdefs or "")
        return _G[gname]
    end
    error(error_mask:format("unknown library alias " .. libname))
end


return sys
