local parallel = {}

local ffi = require "ffi"
local effil = require "effil" --[[../../rocks/lib/luarocks/rocks-5.1/effil/1.2-0/doc/README.md]]
local shm = require "kahlua.shm" --[[shm.lua]]


local LoopingShmemThread = function (o)
    -- Gets closure from `o.method` (or `o[1]`); runs this closure on `cdata` with each `yield` of LoopingShmemThreadPool --
    local memsize = o.memsize or ffi.sizeof(o.ctype)
    local shmem = shm.Shmem(memsize)
    local shmem_id = shmem.id
    local ping, pong, lock = effil.channel(), effil.channel(), effil.channel()
    return {
        thread_nr = o.thread_nr; ping = ping; pong = pong; lock = lock;
        __shmem = shmem; -- need to keep reference, will get GC'd otherwise
        cdata = shmem:cast(o.ctype_cast or o.ctype);
        effil_thread = effil.thread(function (...)
            local shm = require "kahlua.shm" --[[shm.lua]]
            local closure = (o.method or o[1])()
            local shmem = shm.Shmem(memsize, shmem_id, "unlink")
            local cdata = shmem:cast(o.ctype_cast or o.ctype)
            while ping:pop() do
                closure(cdata)
                pong:push(true)
            end
        end)();
        let_compute = function (self)
            self.lock:push(true)
            self.ping:push(true)
        end;
        release = function (self)
            self.lock:pop()
        end;
        join = function (self)
            self.ping:push(nil)
            self.effil_thread:wait()
        end;
        _is_completed = function (self)
            local status, e = self.effil_thread:status()
            return (status == "failed") and error(e) or (status == "completed")
        end;
    }
end


parallel.LoopingShmemThreadPool = function (options)
    -- Docstring goes here lol --
 
    local ERROR_FORBID_ADD = "Cannot add threads to an already active pool"
 
    local _yield_or_exhaust = function (self, action, previous_thread, timeout_ms)
        -- I promise docstrings sometime in the future --
        local next_nr = 1
        if previous_thread then
            previous_thread:let_compute()
            next_nr = (previous_thread.thread_nr % self.n_threads) + 1
        elseif action == "yield" then
            self.add = function () error(ERROR_FORBID_ADD) end
            return self.threads[1], self.threads[1].cdata
        end
        if not timeout_ms then
            for _, thread in ipairs(self.threads) do
                thread:join()
            end
        end
        while true do
            local n_completed = 0
            for _, thread in ipairs(self.threads) do
                if thread:_is_completed() then
                    if thread.pong:size() > 0 then
                        coroutine.yield(thread, thread.cdata)
                    end
                    n_completed = n_completed + 1
                elseif (not self.ordered) or (thread.thread_nr == next_nr) then
                    if thread.pong:pop(timeout_ms, "ms") then
                        coroutine.yield(thread, thread.cdata)
                    elseif timeout_ms and (thread.lock:size() == 0) then
                        return thread, thread.cdata
                    end
                end
            end
            if n_completed == self.n_threads then
                break
            end
        end
    end
 
    return {
        ordered = (options or {}).ordered;
        threads = {}; n_threads = 0;
        add = function (self, o)
            self.n_threads = self.n_threads + 1
            self.threads[self.n_threads] = LoopingShmemThread{
                ctype=o.ctype, ctype_cast=o.ctype_cast,
                memsize=o.memsize, thread_nr=self.n_threads,
                (o.method or o[1]),
            }
        end;
        yield = function (s, ...) return _yield_or_exhaust(s, "yield", ...) end;
        exhaust = function (s) return _yield_or_exhaust(s, "last") end;
    }
end


return parallel
