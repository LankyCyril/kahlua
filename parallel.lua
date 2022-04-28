local parallel = {}

local ffi = require "ffi" -- <../../luajit/src/lib_ffi.c>
local effil = require "effil" -- <../effil/src/cpp/lua-module.cpp>
local shm = require "kahlua.shm" -- <shm.lua>


parallel.LoopingShmemThread = function (o)
    -- Wrapper around an `effil.thread()` that loops `func(cdata)` and passes cdata in an out of `func` via `Shmem` --
 
    local cdef, intype, outtype, func = o.cdef, o.intype, o.outtype, o[1]
    local intype_cast, outtype_cast = o.intype_cast, o.outtype_cast
    if (not intype) or (not outtype) then
        error("LoopingShmemThread: intype and outtype must be defined")
    elseif cdef then
        pcall(function () ffi.cdef(cdef) end)
    end
    local memsize = math.max(ffi.sizeof(intype), ffi.sizeof(outtype))
    local shmem = shm.Shmem(memsize)
    local in_channel, out_channel = effil.channel(), effil.channel()
    local thread = {
        id=shmem.id, polling=false, state=effil.table{status="idle", err=nil},
    }
 
    thread.runner = effil.thread(function ()
        -- Run `func` for each incoming piece of cdata, notified by non-`nil` ping on `in_channel`; finish when next ping is `nil` --
        _ = cdef and require("ffi").cdef(cdef)
        local _shmem = require("kahlua.shm").Shmem(memsize, thread.id, "unlink")
        local cdata, luadata, ping, success = nil, nil, nil, true
        while true do
            luadata, ping = in_channel:pop()
            if ping == nil then
                break
            elseif intype_cast then
                thread.state.status = "casting_in"
                cdata = _shmem:cast(intype_cast)
            else
                thread.state.status = "importing"
                cdata = _shmem:read(intype)
            end
            thread.state.status = "running"
            success, cdata, luadata = pcall(function ()
                return func(cdata, luadata)
            end)
            if not success then
                thread.state.status, thread.state.err = "failed", cdata
                break
            end
            if cdata ~= nil then -- not modified in place
                _shmem:write(cdata, outtype)
            end
            thread.state.status = "presenting"
            out_channel:push(luadata, true)
        end
        thread.state.status = "stopped"
        out_channel:push(nil, nil)
    end)()
 
    thread.join = function (self)
        -- Wait for thread to finish queued loops, then join and stop; does not collect results of function --
        _ = thread.state.err and error(thread.state.err)
        in_channel:push(nil, nil)
        thread.state.status = "joining"
        thread.runner:wait()
        thread.state.status = "stopped"
        _ = thread.state.err and error(thread.state.err)
    end
 
    thread.write = function (self, cdata, luadata)
        -- Non-blocking write that is allowed to fail if thread is busy (not "idle"); returns `true` on success, `nil` otherwise --
        if thread.state.status == "idle" then
            shmem:write(cdata, intype)
            in_channel:push(luadata, true)
            thread.state.status = "data_queued"
            return true
        end
    end
 
    thread.read = function (self, timeout_ms, last)
        -- Read that blocks for `timeout_ms` ms, or indefinitely if `timeout_ms` is `nil`; returns function result or `nil` --
        if last then
            thread:join()
        end
        if not thread.polling then -- XXX TODO nasty race conditions if more than one poller
            thread.polling = true
            local cdata, luadata, ping = nil, nil, nil
            if (timeout_ms == nil) or (thread.state.status == "presenting") then
                luadata, ping = out_channel:pop(timeout_ms, "ms")
            end
            _ = thread.state.err and error(thread.state.err)
            if ping then
                if outtype_cast then
                    thread.state.status = "casting_out"
                    cdata = shmem:cast(outtype_cast)
                else
                    thread.state.status = "exporting"
                    cdata = shmem:read(outtype)
                end
                thread.state.status = "idle"
            end
            thread.polling = false
            return cdata, luadata
        end
    end
 
    thread.status = function (self)
        return thread.state.status, thread.state.err
    end
 
    return thread
end


return parallel
