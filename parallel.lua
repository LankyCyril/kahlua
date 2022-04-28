local parallel = {}

local ffi = require "ffi" -- ../../luajit/src/lib_ffi.c
local effil = require "effil" -- ../effil/src/cpp/lua-module.cpp
local shm = require "kahlua.shm" -- shm.lua


parallel.LoopingShmemThread = function (o)
    -- Wrapper around an `effil.thread()` that loops `func(cdata)` and passes cdata in an out of `func` via `Shmem` --
 
    local cdef, intype, outtype, func = o.cdef, o.intype, o.outtype, o[1]
    local intype_cast, outtype_cast = o.intype_cast, o.outtype_cast
    if (not intype) or (not outtype) then
        error("LoopingShmemThread: intype and outtype must be defined")
    elseif cdef then
        ffi.cdef(cdef)
    end
    local memsize = math.max(ffi.sizeof(intype), ffi.sizeof(outtype))
    local shmem = shm.Shmem(memsize)
    local in_channel, out_channel = effil.channel(), effil.channel()
    local thread = {id=shmem.id, status="idle", polling=false}
 
    thread.runner = effil.thread(function ()
        _ = cdef and require("ffi").cdef(cdef) -- ../../luajit/src/lib_ffi.c
        local _shmem = require("kahlua.shm").Shmem(memsize, thread.id) -- shm.lua
        local data = nil
        while in_channel:pop() ~= nil do
            if intype_cast then
                thread.status = "casting_in"
                data = _shmem:cast(intype_cast)
            else
                thread.status = "importing"
                data = _shmem:read(intype)
            end
            thread.status = "running"
            _shmem:write(func(data), outtype)
            thread.status = "presenting"
            out_channel:push(true)
        end
        thread.status = "stopped"
        out_channel:push(nil)
    end)()
 
    thread.stop = function (self)
        in_channel:push(nil)
        thread.status = "joining"
        thread.runner:wait()
        thread.status = "stopped"
    end
 
    thread.write = function (self, data)
        if thread.status == "idle" then
            shmem:write(data, intype)
            in_channel:push(true)
            thread.status = "data_queued"
            return true
        end
    end
 
    thread.read = function (self, timeout_ms, _type)
        if not thread.polling then
            thread.polling = true
            if out_channel:pop(timeout_ms, "ms") then
                thread.polling = false
                local data = nil
                if outtype_cast then
                    thread.status = "casting_out"
                    data = shmem:cast(outtype_cast)
                else
                    thread.status = "exporting"
                    data = shmem:read(outtype)
                end
                thread.status = "idle"
                return data
            end
        end
    end
 
    return thread
end


return parallel
