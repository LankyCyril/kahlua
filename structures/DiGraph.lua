local DiGraph = {}


local _DiGraph_inc = function (self, parent, child)
    -- Increment weight of edge [parent] -> child --
    local children = self.forward[parent]
    if children then -- parent already has some children
        local weight = children[child]
        if weight then -- edge [parent] -> child already exists
            weight = weight + 1
            children[child] = weight
            return weight -- no back-link updates necessary
        else -- create new edge
            children[child] = 1
            self.outdegrees[parent] = (self.outdegrees[parent] or 0) + 1
        end
    else -- instantiate and update children for parent
        self.forward[parent] = self.options.tabletype(self.options.tableargs)
        self.forward[parent][child] = 1
        self.outdegrees[parent] = (self.outdegrees[parent] or 0) + 1
    end
    -- update back-linking if new edges were created (didn't `return` earlier):
    local parents = self.reverse[child]
    if parents then -- child already has some parents
        parents[parent] = true
    else -- instantiate and update parents for child
        self.reverse[child] = self.options.tabletype(self.options.tableargs)
        self.reverse[child][parent] = true
    end
    self.indegrees[child] = (self.indegrees[child] or 0) + 1
    return 1 -- new edge was created, weight is 1
end


local _DiGraph_add_list = function (self, parent, child, attribute)
    -- Add edge [parent] -> child and add attribute to list; increment weight of edge if already exists --
    local children = self.bag[parent]
    if children then
        local bag = children[child]
        if bag then
            table.insert(bag, attribute)
        else
            children[child] = {attribute}
        end
    else
        self.bag[parent] = self.options.tabletype(self.options.tableargs)
        self.bag[parent][child] = {attribute}
    end
    return _DiGraph_inc(self, parent, child)
end


local _DiGraph_add_table = function (self, parent, child, attribute)
    -- Add edge [parent] -> child and add attribute to table; increment weight of edge if already exists --
    local children = self.bag[parent]
    if children then
        local bag = children[child]
        if bag then
            bag[attribute] = (bag[attribute] or 0) + 1
        else
            children[child] = {[attribute]=1}
        end
    else
        self.bag[parent] = self.options.tabletype(self.options.tableargs)
        self.bag[parent][child] = {[attribute]=1}
    end
    return _DiGraph_inc(self, parent, child)
end


local _DiGraph_dec = function (self, parent, child)
    -- Decrement weight of edge [parent] -> child if exists, remove edge if weight becomes 0 --
    local children = self.forward[parent]
    if children then -- parent already has some children
        local weight = children[child]
        if weight then -- edge [parent] -> child exists
            if weight ~= 1 then -- decrementing will not reset edge to 0
                weight = weight - 1
                children[child] = weight
                return weight
            else -- edge resets to 0 and should be removed
                children[child] = nil -- remove forward link
                local parents = self.reverse[child]
                if parents then
                    parents[parent] = nil -- remove back-link
                end
                -- decrement parent outdegree, set to nil if becomes zero:
                local parent_outdegree = (self.outdegrees[parent] or 1)
                if parent_outdegree ~= 1 then
                    self.outdegrees[parent] = parent_outdegree - 1
                else
                    self.outdegrees[parent] = nil
                end
                -- decrement child indegree, set to nil if becomes zero:
                local child_indegree = self.indegrees[child]
                if child_indegree ~= 1 then
                    self.indegrees[child] = child_indegree - 1
                else
                    self.indegrees[child] = nil
                end
                return 0 -- report decremented weight as zero
            end
        end
    end
    return nil, "No edge to decrement" -- fallback for all no-op situations
end


local _DiGraph_del = function (self, parent, child)
    -- Remove edge [parent] -> child and all its attributes --
    local children = self.forward[parent]
    if children then -- parent already has some children
        local weight = children[child]
        if weight then -- edge [parent] -> child exists
            children[child] = 1 -- stage weight as 1 so _DiGraph_dec will delete
            _DiGraph_dec(self, parent, child)
        end
    end
    children = self.bag[parent]
    if children then
        children[child] = nil
    end
end


local _DiGraph_iteredges_noattributes = function (self)
    return coroutine.wrap(function ()
        for parent, children in self.options.tableiter(self.forward) do
            for child, weight in self.options.tableiter(children) do
                coroutine.yield(parent, child, weight)
            end
        end
    end)
end


local _DiGraph_iteredges = function (self)
    return coroutine.wrap(function ()
        for parent, child, weight in _DiGraph_iteredges_noattributes(self) do
            coroutine.yield(
                parent, child, weight, (self.bag[parent] or {})[child] or {}
            )
        end
    end)
end


local _DiGraph_to_dot_inner_printattr_list = function (self, file, rename_nodes)
    local node_repr_mask = "\t%s -> %s [weight=%s attributes=%s];\n"
    for parent, child, weight, attributes in _DiGraph_iteredges(self) do
        local attribute_repr = table.concat(attributes, ",")
        if attribute_repr == "" then
            attribute_repr = "nil"
        end
        file:write(node_repr_mask:format(
            rename_nodes[parent] or parent,
            rename_nodes[child] or child,
            weight,
            attribute_repr
        ))
    end
end


local _DiGraph_to_dot_inner_printattr_table = function (self, file, rename_nodes)
    local node_repr_mask = "\t%s -> %s [weight=%s attributes=%s];\n"
    for parent, child, weight, attributes in _DiGraph_iteredges(self) do
        local attribute_repr = ""
        for k, v in pairs(attributes) do
            attribute_repr = attribute_repr .. (",%s(%s)"):format(k, v)
        end
        if attribute_repr == "" then
            attribute_repr = "nil"
        else
            attribute_repr = attribute_repr:sub(2)
        end
        file:write(node_repr_mask:format(
            rename_nodes[parent] or parent,
            rename_nodes[child] or child,
            weight,
            attribute_repr
        ))
    end
end


local _DiGraph_to_dot_inner_printattr_raw = function (self, file, rename_nodes)
    local node_repr_mask = "\t%s -> %s [weight=%s attributes=%s];\n"
    for parent, child, weight in _DiGraph_iteredges_noattributes(self) do
        local attribute_repr = (self.bag[parent] or {})[child] or nil
        file:write(node_repr_mask:format(
            rename_nodes[parent] or parent,
            rename_nodes[child] or child,
            weight,
            attribute_repr
        ))
    end
end


local _DiGraph_to_dot_inner_noprintattr = function (self, file, rename_nodes)
    local node_repr_mask = "\t%s -> %s [weight=%s];\n"
    for parent, child, weight in _DiGraph_iteredges_noattributes(self) do
        file:write(node_repr_mask:format(
            rename_nodes[parent] or parent,
            rename_nodes[child] or child,
            weight
        ))
    end
end


local _DiGraph_to_dot = function (self, file, options)
    -- Write out DiGraph in dot format --
    local node_repr_mask = "\t%s -> %s [weight=%s];\n"
    local options = options or {}
    local rename_nodes = options.rename_nodes or {}
    file:write(
        ("digraph %s {\n"):format(options.name or "graph")
    )
    if options.print_attributes then
        if self.options.bagtype == "list" then
            _DiGraph_to_dot_inner_printattr_list(self, file, rename_nodes)
        elseif self.options.bagtype == "table" then
            _DiGraph_to_dot_inner_printattr_table(self, file, rename_nodes)
        else
            _DiGraph_to_dot_inner_printattr_raw(self, file, rename_nodes)
        end
    else
        _DiGraph_to_dot_inner_noprintattr(self, file, rename_nodes)
    end
    file:write("}\n")
end


DiGraph.new = function (options)
    -- Create DiGraph using tables; implements edge weights and uncategorized lists of edge attributes --
    local options = options or {}
    options.tabletype = options.tabletype or function () return {} end
    options.tableargs = options.tableargs or {}
    options.tableiter = options.tableiter or pairs
    options.bagtype = options.bagtype or "list"
    if (options.bagtype ~= "list") and (options.bagtype ~= "table") then
        local err_mask = "kahlua.structures.DiGraph.new(): unknown bagtype '%s'"
        error(err_mask:format(options.bagtype))
    end
    return {
        forward = options.tabletype(options.tableargs), -- [[u]->w]->weight
        reverse = options.tabletype(options.tableargs), -- [[w]<-u]->boolean
        bag = options.tabletype(options.tableargs), -- [[u]->w]->{attributes}
        indegrees = options.tabletype(options.tableargs), -- count<-[u]
        outdegrees = options.tabletype(options.tableargs), -- [u]->count
        options = options,
        inc = _DiGraph_inc,
        add = (options.bagtype == "list") and
            _DiGraph_add_list or _DiGraph_add_table,
        dec = _DiGraph_dec,
        del = _DiGraph_del,
        get = function (self, p, c) return (self.forward[p] or {})[c] end,
        iteredges = _DiGraph_iteredges,
        to_dot = _DiGraph_to_dot,
    }
end


return DiGraph
