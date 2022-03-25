local OrderedTable = {}


local _new_OrderedTable_Unshrinkable = function ()
    -- Create OrderedTable with forward linked list of keys --
    local _meta = {
        firstkey = nil, lastkey = nil, keychain = {}
    }
    _meta.__newindex = function (self, key, value)
        rawset(self, key, value)
        if _meta.keychain[key] == nil then -- has never been added and deleted
            if _meta.firstkey == nil then -- table is empty so far
                _meta.firstkey = key -- point start to this key
            end
            if _meta.lastkey ~= nil then
                _meta.keychain[_meta.lastkey] = key -- grow chain from lastkey
            end
            _meta.lastkey = key -- point end to this key
            _meta.keychain[key] = nil -- no next key
        end
    end
    return setmetatable({}, _meta)
end


local _new_OrderedTable_Shrinkable = function ()
    -- Create OrderedTable with forward and reverse linked lists of keys --
    local _meta = {
        firstkey = nil, lastkey = nil, keychain = {}, reverse_keychain = {}
    }
    _meta.__newindex = function (self, key, value)
        rawset(self, key, value)
        if _meta.keychain[key] == nil then -- has never been added and deleted
            if _meta.firstkey == nil then -- table is empty so far
                _meta.firstkey = key -- point start to this key
            end
            if _meta.lastkey ~= nil then
                _meta.keychain[_meta.lastkey] = key -- grow chain from lastkey
                _meta.reverse_keychain[key] = _meta.lastkey -- mirror chain
            end
            _meta.lastkey = key -- point end to this key
            _meta.keychain[key] = nil -- no next key
        end
    end
    return setmetatable({}, _meta)
end


OrderedTable.new = function (options)
    local options = options or {}
    options.shrinkable = options.shrinkable or true
    if options.shrinkable then
        return _new_OrderedTable_Shrinkable()
    else
        return _new_OrderedTable_Unshrinkable()
    end
end


OrderedTable.rip = function (ot, ...)
    -- Ripple delete element(s), rip out element(s), RIP --
    local _meta = getmetatable(ot)
    if _meta and _meta.keychain and _meta.reverse_keychain then
        for _, key in ipairs({...}) do
            -- unset element:
            rawset(ot, key, nil)
            -- update firstkey and lastkey pointers if necessary:
            if key == _meta.firstkey then
                _meta.firstkey = _meta.keychain[key]
            end
            if key == _meta.lastkey then
                _meta.lastkey = _meta.reverse_keychain[key]
            end
            -- make new direct link:
            local source = _meta.reverse_keychain[key]
            local destination = _meta.keychain[key]
            _meta.reverse_keychain[key], _meta.keychain[key] = nil
            if source ~= nil then
                _meta.keychain[source] = destination
            end
            if destination ~= nil then
                _meta.reverse_keychain[destination] = source
            end
        end
    else
        local error_mask = "kahlua.structures.OrderedTable.rip: %s"
        error(error_mask:format("object is not an OrderedTable.Shrinkable"))
    end
end


OrderedTable.opairs = function (ot)
    -- Iterate over pairs in insertion order --
    local _meta = getmetatable(ot)
    if _meta and _meta.keychain then
        local stateless_iterator = function (ot, key)
            local nextkey
            if key == nil then -- iterator at starting point
                nextkey = _meta.firstkey
            else -- iterator arrived at next step
                nextkey = _meta.keychain[key] -- advance, maybe to a nil
            end
            -- find next non-deleted value:
            while (nextkey ~= nil) and (ot[nextkey] == nil) do
                nextkey = _meta.keychain[nextkey]
            end
            if nextkey ~= nil then -- found a non-nil key and a non-nil value
                return nextkey, ot[nextkey]
            else -- reached end of keychain
                return nil
            end
        end
        return stateless_iterator, ot, nil -- nil is a starting point
    else
        local error_mask = "kahlua.structures.OrderedTable.opairs: %s"
        error(error_mask:format("object is not an OrderedTable"))
    end
end


OrderedTable.getkeys = function (ot)
    local _meta = getmetatable(ot)
    return _meta.firstkey, _meta.keychain, _meta.lastkey
end


OrderedTable.inspect = function (ot, target_keychain)
    -- Iterate over OrderedTable's keychain --
    local _meta = getmetatable(ot)
    local error_mask = "kahlua.structures.OrderedTable.inspect: %s"
    if _meta == nil then
        error(error_mask:format("object does not have a metatable"))
    end
    if (target_keychain == "keychain") or (target_keychain == nil) then
        keychain, key = _meta.keychain, _meta.firstkey
    elseif target_keychain == "reverse_keychain" then
        keychain, key = _meta.reverse_keychain, _meta.lastkey
    else
        error(error_mask:format("unrecognized keychain: " .. target_keychain))
    end
    if keychain == nil then
        error(error_mask:format("object missing keychain: " .. target_keychain))
    end
    return coroutine.wrap(function ()
        while key ~= nil do
            coroutine.yield(key)
            key = keychain[key]
        end
    end)
end


return OrderedTable
