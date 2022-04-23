local sys = {}

math.randomseed(os.time() + os.clock())
local random = math.random


local random_global_name = function (libname)
    -- Almost guaranteed unique name (same number of bits as UUID4) --
    local r = math.ceil(random() * (2^128))
    return ("%.0f_%s"):format(r, libname)
end


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


local ffi = sys.loadglobal "ffi"
ffi.cdef "char* strcpy(char* d, const char* s); size_t strlen(const char* s);"
sys.C = {
    U64 = ffi.typeof("uint64_t");
    MEDCHARRLEN = 2 ^ 24 - 1;
    BIGCHARRLEN = 2 ^ 31 - 1;
    MedChArr = function () return ffi.new("char[?]", 2 ^ 24 - 1) end;
    BigChArr = function () return ffi.new("char[?]", 2 ^ 31 - 1) end;
    ChArr = function (length) return ffi.new("char[?]", length) end;
    charr2str = ffi.string;
    strcpy = ffi.C.strcpy;
    strlen = ffi.C.strlen;
}


sys.uuid4 = function ()
    -- Quick generation of UUID4 --
    return ("%08x-%04x-4%03x-%x%03x-%012x"):format(
        random(0, 0xffffffff), random(0, 0xffff),
        random(0, 0xfff), random(8, 11), random(0, 0xfff),
        random(0, 0xffffffffffff)
    )
end


sys.loadffi = function (libname, dealiased, tester, cdefs)
    -- Load and add `libname` to the global environment --
    local ffi = sys.loadglobal "ffi"
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


sys.is_64bit_math_valid = function ()
    -- Check that ffi/bitop operations return correct 64-bit values --
    local ffi = sys.loadglobal "ffi"
    local error_mask = "kahlua.sys.is_64bit_math_valid: error: %s"
    local a = bit.lshift(ffi.new("uint64_t", 1), 31) - 1
    local b = bit.lshift(a, 30) + bit.rshift(a, 3) - 4096
    local c = ffi.new("int64_t", -1)
    local d = bit.band(0x00000000ffffffff, ffi.new("int64_t", -1201018566))
    if bit.tohex(b) ~= "1fffffffcfffefff" then
        return nil, error_mask:format("bit shifting of 64-bit integers")
    elseif bit.tobit(b) ~= -805310465 then
        return nil, error_mask:format("getting low 4 bytes of a 64-bit integer")
    elseif (bit.tohex(c) ~= ("f"):rep(16)) or (tonumber(d) ~= 3093948730) then
        return nil, error_mask:format("representing int64_t negative numbers")
    else
        return true
    end
end


sys.fdef = function (args)
    -- Create function with default named parameters: f = fdef {a="a", function (o) return o.a end}; c = f {a="b"}; --
    if (#args ~= 1) or (type(args[1]) ~= "function") then
        error("kahlua.sys.fdef accepts exactly one function body")
    else
        return function (o)
            local o = o
            for k, v in pairs(args) do
                if (k ~= 1) and (o[k] == nil) then
                    o[k] = v
                end
            end
            return args[1](o)
        end
    end
end


sys.check_output = function (command, method)
    -- Like Python's subprocess.check_output(..., shell=True) --
    local call = io.popen(command)
    if (method == "iterate") or (method == "i") then
        return coroutine.wrap(function ()
            for line in call:lines() do
                coroutine.yield(line)
            end
            call:close()
        end)
    elseif (method == "split") or (method == "s") or (method == "\n") then
        local data = {}
        for line in call:lines() do
            table.insert(data, line)
        end
        call:close()
        return data
    else
        local data = call:read("*a")
        call:close()
        return data
    end
end


sys.shellquote = function (path)
    -- Leverage `printf '%q'` to shell-escape (quote) anything; yes, it is janky --
    local bus = os.tmpname()
    local handle = io.open(bus, "w")
    handle:write(path)
    handle:close()
    local call = io.popen('`which printf` %q "$(cat ' .. bus .. ')"')
    local quoted = call:read()
    call:close()
    os.remove(bus)
    return quoted
end


return sys
