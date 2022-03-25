local itertools = {}


local _count_valid_arg = function (x)
    return (type(x or 1) == "number")
end


local _count_error = function (a, b, c)
    local error_mask = "%s(%s, %s, %s): could not interpret these arguments"
    error(error_mask:format("kahlua.itertools.count", a, b, c))
end


local _count_internal = function (a, b, c)
    -- Emulate Python counters directly: range, enumerate, count --
    if not (_count_valid_arg(b) and _count_valid_arg(c)) then
        _count_error(a, b, c)
    elseif (type(a) == "function") or (type(a) == "table") then
        local i = b or 1
        c = c or 1
        return coroutine.wrap(function ()
            if type(a) == "function" then
                for item in a do
                    coroutine.yield(i, item)
                    i = i + c
                end
            else
                for k, v in pairs(a) do
                    coroutine.yield(i, k, v)
                    i = i + c
                end
            end
        end)
    elseif _count_valid_arg(a) then
        return coroutine.wrap(function ()
            for i = (a or 1), (b or math.huge), (c or 1) do
                coroutine.yield(i)
            end
        end)
    else
        _count_error(a, b, c)
    end
end


itertools.count = function (a, b, c)
    -- Emulate Python counters (range, enumerate, count) and expose params --
    local _counter = {}
    if (type(a) == "function") or (type(a) == "table") then
        _counter.iterable, _counter.min, _counter.step = a, (b or 1), (c or 1)
        _counter.max, _counter.total = math.huge, math.huge
    else
        _counter.min, _counter.max = (a or 1), (b or math.huge)
        _counter.step = c or 1
        if _counter.max == math.huge then
            _counter.total = math.huge
        else
            _counter.total = math.ceil(
                (_counter.max - _counter.min + 1) / _counter.step
            )
        end
    end
    return setmetatable(_counter, {__call = _count_internal(a, b, c)})
end


local _progressbar_interpret_options = function (iterable, options)
    -- Fill in default options for progressbar --
    local opt = options or {}
    opt.clock = opt.clock or os.clock
    opt.minwait = opt.minwait or 1
    opt.total = opt.total or iterable.total or math.huge
    opt.desc, opt.unit = opt.desc or "Progress", opt.unit or "iterations"
    opt.funcs = opt.funcs or {}
    if (not opt.fmt) and (opt.total == math.huge) then
        opt.fmt = "$D: $B $C $U [$Es]"
    elseif (not opt.fmt) and (opt.total ~= math.huge) then
        opt.fmt = "$D: $B $P ($C/$T $U) [$E<$Rs]"
    end
    return opt
end


local _progressbar_print_progress = function (i, elapsed, opt, endchar)
    -- Print single line of progressbar when update is triggered --
    local bar, remaining, percentage
    if (opt.total == math.huge) then
        bar, percentage, remaining = "\b", "\b", "?"
    elseif (elapsed == 0) or (i == 0) then
        bar, percentage, remaining = ("."):rep(10), "0.0%", "-0"
    else
        local f = math.floor(10 * i / opt.total)
        bar = ("#"):rep(f) .. ("."):rep(10 - f)
        percentage = ("%.1f%%"):format(i * 100 / opt.total)
        remaining = ("%.1f%%"):format(elapsed * (opt.total - i) / i)
    end
    local report = opt.fmt
        :gsub("$D", opt.desc) :gsub("$B", bar) :gsub("$P", percentage)
        :gsub("$C", ("%d"):format(i)) :gsub("$T", opt.total)
        :gsub("$E", ("%.1f"):format(elapsed)) :gsub("$R", remaining)
        :gsub("$U", opt.unit)
    for n, func in ipairs(opt.funcs) do
        report = report:gsub(("$%d"):format(n), tostring(func()))
    end
    io.stderr:write(report .. endchar)
end


itertools.progressbar = function (iterable, options)
    -- Wrap iterable with progressbar --
    local opt = _progressbar_interpret_options(iterable, options)
    local i, baseclock, lastclock, elapsed = 0, opt.clock(), 0, 0
    return coroutine.wrap(function ()
        _progressbar_print_progress(i, elapsed, opt, "\r")
        for item in iterable do -- TODO accommodate multiple items
            i = i + 1
            elapsed = opt.clock() - baseclock
            if (elapsed - lastclock) >= opt.minwait then
                lastclock = elapsed
                _progressbar_print_progress(i, elapsed, opt, "\r")
            end
            coroutine.yield(item)
        end
        _progressbar_print_progress(i, elapsed, opt, "\n")
    end)
end


return itertools
