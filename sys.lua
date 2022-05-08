local sys = {--[[
    Defines helper methods.
    Seeds math.random.
    Imports a number of stlib C functions (`kahlua.sys.C`).
]]}

local ffi = require "ffi"
local random = math.random
local unpack = unpack or table.unpack
math.randomseed(os.time() + os.clock())


sys.gcrun = function (main, ...)
    -- Run entrypoint function, collect garbage explicitly, exit with result of entrypoint function --
    local args = {...}
    local success, returncode = pcall(function () return main(unpack(args)) end)
    collectgarbage()
    collectgarbage()
    _ = success and os.exit(returncode or 0) or error(returncode)
end


sys.C = {
    strerror = ffi.cdef "char *strerror(int errnum);" or ffi.C.strerror;
    strcpy = ffi.cdef("char *strcpy(char *d, const char *s)") or ffi.C.strcpy;
    strlen = ffi.cdef("size_t strlen(const char *s);") or ffi.C.strlen;
}


sys.uuid4 = function ()
    -- Quick generation of UUID4 --
    return ("%08x-%04x-4%03x-%x%03x-%012x"):format(
        random(0, 0xffffffff), random(0, 0xffff), random(0, 0xfff),
        random(8, 11), random(0, 0xfff), random(0, 0xffffffffffff)
    )
end


sys.is_64bit_math_valid = function ()
    -- ROUGHLY check that ffi/bitop operations return correct 64-bit values --
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


sys.shellquote = function (s)
    -- Shell-escape (quote) anything; see https://stackoverflow.com/a/3669819 --
    return "'" .. s:gsub("'", "'\\''") .. "'"
end


sys.printf_q = function (s)
    -- Leverage `printf '%q'` to shell-escape (quote) anything; yes, it is janky, but uses the "proper" tool --
    local bus = os.tmpname()
    local handle = io.open(bus, "w")
    handle:write(s)
    handle:close()
    local call = io.popen('`which printf` %q "$(cat ' .. bus .. ')"')
    local quoted = call:read()
    call:close()
    os.remove(bus)
    return quoted
end


return sys
