-- XXX NOTE: work in progress --
local itertools = {}


itertools.cycle = function (iterator, options) return coroutine.wrap(function ()
    local options = options or {}
    if options.indices and options.keys then
        error("itertools.cycle: `keys` & `indices` are mutually exclusive")
    elseif options.indices then
        if options.values then
            while true do for i, v in ipairs(iterator) do
                coroutine.yield(i, v)
            end end
        else
            while true do for i in ipairs(iterator) do
                coroutine.yield(i)
            end end
        end
    elseif options.keys then
        if options.values then
            while true do for k, v in pairs(iterator) do
                coroutine.yield(k, v)
            end end
        else
            while true do for k in pairs(iterator) do
                coroutine.yield(k)
            end end
        end
    elseif options.values then
        while true do for _, v in pairs(iterator) do
            coroutine.yield(v)
        end end
    else
        while true do -- TODO: restartable
            for v in iterator do -- TODO: multiple values
                coroutine.yield(v)
            end
        end
    end
end) end


return itertools
