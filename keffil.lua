local keffil = {}

local effil = require "effil"
local sleep = effil.sleep


keffil.EffilThreadPool = function (max_threads, poll_milliseconds) return {
    -- Thread pool --
 
    max_threads = max_threads; n_active = 0;
    pool = {}; active = {};
    poll_milliseconds = poll_milliseconds or 1;
 
    _inc = function (self, thread)
        if not self.active[thread] then
            self.active[thread], self.n_active = true, self.n_active + 1
        end
        return thread
    end;
 
    _dec = function (self, thread)
        if self.active[thread] then
            self.active[thread], self.n_active = nil, self.n_active - 1
        end
        return thread
    end;
 
    completed = function (self)
        return coroutine.wrap(function ()
            for thread in pairs(self.pool) do
                local tstatus = thread:status()
                if tstatus == "completed" then
                    coroutine.yield(self:_dec(thread))
                elseif tstatus ~= "running" then
                    error("Acting on status "..tstatus.." not implemented")
                end
            end
        end)
    end;
 
    add = function (self, newthread, ...)
        while self.n_active >= self.max_threads do
            for _ in self:completed() do
                effil.sleep(self.poll_milliseconds, "ms")
            end
        end
        self.pool[self:_inc(newthread(...))] = true
    end;
 
    pop = function (self, thread)
        local result = thread:get()
        self.pool[self:_dec(thread)] = nil
        return result
    end;
 
    wait = function (self)
        for thread in pairs(self.pool) do
            self:_dec(thread):wait()
        end
    end;
 
} end


return keffil
