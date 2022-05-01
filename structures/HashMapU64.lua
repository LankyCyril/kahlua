local HashMapU64 = {}

local sys = require "kahlua.sys" -- <sys.lua>
local ffi = require "ffi" -- <../../luajit/src/lib_ffi.c>

local tobit, band, bor, lshift, rshift, typeof =
    bit.tobit, bit.band, bit.bor, bit.lshift, bit.rshift, ffi.typeof
local U64, S64 = typeof("uint64_t"), typeof("int64_t")

-- fail at require time if 64-bit math does not work:
local math_valid, err = sys.is_64bit_math_valid()
if not math_valid then
    error(err)
end


local _HashMapU64_nontypechecked = function ()
    -- HashMapU64 via nested tables, assumes keys are uint64_t, doesn't check --
    return setmetatable({}, {
        __newindex = function (self, key, value)
            -- high and low may be represented as negative numbers, technically;
            -- this does not affect storing keys or retrieving values by direct
            -- indexing, but requires caution when iterating.
            -- See __index() below for direct retrieval;
            -- see HashMapU64.hmpairs() for iteration.
            local high, low = tobit(rshift(key, 32)), tobit(key)
            local subtable = rawget(self, high)
            if subtable then
                subtable[low] = value
            else
                rawset(self, high, {[low]=value})
            end
        end,
        __index = function (self, key)
            -- high and low may be represented as negative numbers, technically;
            -- this does not affect retrieving values by direct indexing, since
            -- there is a 1-to-1 mapping between the high/low 32 bits of the key
            -- and Lua's number representation, be it positive or negative.
            local subtable = rawget(self, tobit(rshift(key, 32)))
            if subtable then
                return subtable[tobit(key)]
            end
        end
    })
end


local _HashMapU64_typechecked = function ()
    -- HashMapU64 via nested tables, keys must be uint64_t, throws error otherwise --
    local errmsg = "kahlua.structures.HashMapU64: keys must be uint64_t"
    return setmetatable({}, {
        __newindex = function (self, key, value)
            if (type(key) ~= "cdata") or (typeof(key) ~= U64) then
                error(errmsg)
            end
            local high, low = tobit(rshift(key, 32)), tobit(key)
            local subtable = rawget(self, high)
            if subtable then
                subtable[low] = value
            else
                rawset(self, high, {[low]=value})
            end
        end,
        __index = function (self, key)
            if (type(key) ~= "cdata") or (typeof(key) ~= U64) then
                error(errmsg)
            end
            local subtable = rawget(self, tobit(rshift(key, 32)))
            if subtable then
                return subtable[tobit(key)]
            end
        end
    })
end


HashMapU64.new = function (options)
    -- Table supporting 64-bit keys via nested 32-bit key tables --
    local options = options or {}
    if (options.checktype == true) or (options.checktype == nil) then
        return _HashMapU64_typechecked()
    else
        return _HashMapU64_nontypechecked()
    end
end


HashMapU64.hmpairs = function (hm64)
    -- Iterate over pairs in a HashMapU64 table --
    return coroutine.wrap(function ()
        for high, subtable in pairs(hm64) do
            -- high and low may be represented as negative numbers by Lua.
            -- Since the original key was unsigned, and we need to recombine
            -- high and low as unsigned values, we must represent them correctly
            -- for bitwise operations.
            -- ffi.new("uint64_t", value) is undefined behavior if the value is
            -- negative; e.g. the OpenResty branch of LuaJIT may convert any
            -- negative value to a uint64_t value of 0x8000000000000000.
            -- However, when retrieving values for bitwise operations, they can
            -- be read as signed integers (defined behavior); for example,
            -- any LuaJIT branch should report ffi.new("int64_t", -1) as
            -- 0xffffffffffffffff.
            -- This is also checked by kahlua.sys.is_64bit_math_valid().
            local shifted_high = lshift(S64(high), 32)
            for low, value in pairs(subtable) do
                coroutine.yield(
                    bor(shifted_high, band(0x00000000ffffffff, S64(low))), value
                )
            end
        end
    end)
end


HashMapU64.isempty = function (hm64)
    -- Check if HashMapU64 is empty --
    for high, subtable in pairs(hm64) do
        for low, value in pairs(subtable) do
            return false
        end
    end
    return true
end


return HashMapU64
