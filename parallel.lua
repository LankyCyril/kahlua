local parallel = {}

local ffi = require "ffi"
local effil = require "effil" --[[../../rocks/lib/luarocks/rocks-5.1/effil/1.2-0/doc/README.md]]
local shm = require "kahlua.shm" --[[shm.lua]]


parallel.LoopingShmemThread = function (o)
    -- Loop function `func(cdata, ping, pong)` that resumes on ping, modifies cdata in shared memory in-place, and pauses with pong --
    local shmem = shm.Shmem(ffi.sizeof(o.ctype))
    local shmem_id = shmem.id
    local ping, pong, lock = effil.channel(), effil.channel(), effil.channel()
    return {
        ping = ping; pong = pong; lock = lock;
        __shmem = shmem; -- need to keep reference, will get GC'd otherwise
        cdata = shmem:cast(o.ctype_cast or o.ctype);
        thread = effil.thread(function (...)
            local ffi = require "ffi"
            ffi.cdef(o.cdefs or "")
            local shm = require "kahlua.shm" --[[shm.lua]]
            local shmem = shm.Shmem(ffi.sizeof(o.ctype), shmem_id, "unlink")
            local cdata = shmem:cast(o.ctype_cast or o.ctype)
            ;(o.func or o[1])(
                cdata,
                function () return ping.pop(ping) end,
                function () return pong.push(pong, true) end
            )
        end)();
        release = function (self)
            while self.lock:size() > 0 do
                self.lock:pop()
            end
        end;
        _is_completed = function (self)
            local status, e = self.thread:status()
            return (status == "failed") and error(e) or (status == "completed")
        end;
    }
end


parallel.LoopingShmemThreadPool = function (options)
    -- Docstring goes here lol --
 
    ffi.cdef(options.cdefs or "")
    local ERROR_FORBID_ADD = "Cannot add threads to an already active pool"
 
    local _yield_or_exhaust = function (self, action, previous_thread, timeout_ms)
        -- I promise docstrings sometime in the future --
        if previous_thread then
            previous_thread.lock:push(true)
            previous_thread.ping:push(true)
        elseif action == "yield" then
            self.add = function () error(ERROR_FORBID_ADD) end
            return self.threads[1], self.threads[1].cdata
        end
        if not timeout_ms then
            for _, thread in ipairs(self.threads) do
                thread.ping:push(nil)
                thread.thread:wait()
            end
        end
        while true do
            local n_completed = 0;
            for _, thread in ipairs(self.threads) do
                if thread:_is_completed() then
                    if thread.pong:size() > 0 then
                        coroutine.yield(thread, thread.cdata)
                    end
                    n_completed = n_completed + 1
                elseif thread.pong:pop(timeout_ms) then
                    coroutine.yield(thread, thread.cdata)
                elseif timeout_ms and (thread.lock:size() == 0) then
                    return thread, thread.cdata
                end
            end
            if n_completed == self.n_threads then
                break
            end
        end
    end
 
    return {
        cdefs = options.cdefs; n_threads = 0; threads = {};
        add = function (self, o)
            self.n_threads = self.n_threads + 1
            self.threads[self.n_threads] = parallel.LoopingShmemThread{
                cdefs=self.cdefs, ctype=o.ctype, ctype_cast=o.ctype_cast, o[1],
            }
        end;
        yield = function (s, ...) return _yield_or_exhaust(s, "yield", ...) end;
        exhaust = function (s) return _yield_or_exhaust(s, "last") end;
    }
end


return parallel
