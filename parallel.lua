local parallel = {--[[
    Implements multithreading with cdata objects via POSIX shared memory.
 
    Requires [effil](https://github.com/effil/effil).
    NOTE: tested on effil built from the Feb 27, 2022 commit
    c5e51233415e23a0b712350a954d6820ddffd6a0.
    At the moment of writing, luarocks has an older version (built on
    Sep 20, 2020) which causes unexplainable segfaults. Until effil is updated
    in luarocks, it is highly advised to build it from source.
]]}

local ffi = require "ffi"
local effil = require "effil"
local shm = require "kahlua.shm" --[[shm.lua]]


local LoopingShmemThread = function (o)
    -- Gets closure from `o.method` (or `o[1]`); runs this closure on `cdata` with each `yield` of LoopingShmemThreadPool --
 
    local memsize = o.memsize or ffi.sizeof(o.ctype)
    local shmem = shm.Shmem(memsize)
    local shmem_id = shmem.id
    local _ping, _pong, _lock =
        effil.channel(), effil.channel(), effil.channel()
 
    return {
        thread_no = o._nr; _nr = o._nr;
        _ping = _ping; _pong = _pong; _lock = _lock;
        __shmem = shmem; -- need to keep reference, will get GC'd otherwise
        cdata = shmem:cast(o.ctype_cast or o.ctype);
        effil_thread = effil.thread(function (...)
            local shm = require "kahlua.shm" --[[shm.lua]]
            local closure = (o.method or o[1])()
            local shmem = shm.Shmem(memsize, shmem_id, "unlink")
            local cdata = shmem:cast(o.ctype_cast or o.ctype)
            _pong:push(true) -- come-alive signal
            while _ping:pop() do
                closure(cdata)
                _pong:push(true)
            end
        end)();
        let_compute = function (self)
            self._lock:push(true)
            self._ping:push(true)
        end;
        release = function (self)
            self._lock:pop()
        end;
        join = function (self)
            self._ping:push(nil)
            self.effil_thread:wait()
        end;
        _is_completed = function (self)
            local status, e = self.effil_thread:status()
            return (status == "failed") and error(e) or (status == "completed")
        end;
    }
end


parallel.LoopingShmemThreadPool = function (options) --[[
    LoopingShmemThreadPool{ordered=<bool>}: initializes an empty pool for threads that operate on cdata
    - The option `ordered` dictates whether the threads can be mapped to
      incoming data arbitrarily or circularly in the order they were added
      to the pool. ]]
 
    local ERROR_FORBID_ADD = "Cannot add threads to an already active pool"
 
    local _yield_or_exhaust = function (self, action, previous_thread, timeout_ms)
        -- Defines logic for `:yield()` and `:exhaust()`, see below; yields all currently available (thread, cdata) pairs --
        local next_nr = 1
        if previous_thread then
            previous_thread:let_compute()
            next_nr = (previous_thread._nr % self.n_threads) + 1
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
                    if thread._pong:size() > 0 then
                        coroutine.yield(thread, thread.cdata)
                    end
                    n_completed = n_completed + 1
                elseif (not self.ordered) or (thread._nr == next_nr) then
                    if thread._pong:pop(timeout_ms, "ms") then
                        coroutine.yield(thread, thread.cdata)
                    elseif timeout_ms and (thread._lock:size() == 0) then
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
        ordered = (options or {}).ordered; threads = {}; n_threads = 0;
        add = function (self, o) --[[
            LoopingShmemThreadPool:add{ctype=<str>, ctype_cast=<str>,
            memsize=<int>, <closure-generating-function>}: adds thread to pool.
            - At minimum, `ctype` and a function must be passed.
            - `ctype_cast` defaults to `ctype`, but can be different (e.g.,
              you'll want to cast "struct A" as "struct A*").
            - The closure generating function accepts no arguments; it runs in
              its own Lua state and must also define the ctype either before
              returning the closure or inside of it.
            - The closure itself must accept exactly one argument, the shared
              cdata itself, which is both readable and writeable. ]]
            self.n_threads = self.n_threads + 1
            self.threads[self.n_threads] = LoopingShmemThread {
                ctype=o.ctype, ctype_cast=o.ctype_cast, memsize=o.memsize,
                _nr=self.n_threads, (o.method or o[1]),
            }
            self.threads[self.n_threads]._pong:pop()
        end;
        yield = function (self, previous_thread, timeout_ms) --[[
            Assumes `previous_thread` has new input data written to its cdata,
            takes this thread back into the pool and lets it compute. Yields
            all possible (thread, cdata) pairs for the other threads that have
            completed a cycle (waiting up to `timeout_ms` milliseconds for them
            to report). Returns next available thread (whose cdata has already
            been declared OK to overwrite by calling `thread:release()`). ]]
            return _yield_or_exhaust(self, "yield", previous_thread, timeout_ms)
        end;
        exhaust = function (self) --[[
            Waits for all remaining threads to finish computing, yields all of
            their (thread, cdata) pairs. ]]
            return _yield_or_exhaust(self, "last")
        end;
    }
end


return parallel
