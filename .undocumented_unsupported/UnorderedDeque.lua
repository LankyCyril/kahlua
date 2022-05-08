-- XXX NOTE: Work in progress XXX --

local UnorderedDeque = {}


UnorderedDeque.new = function (maxlength)
    return {
        maxlength = maxlength or error(
            "kahlua.structures.UnorderedDeque.new(): no deque length provided"
        ),
        length = 0,
        pointer = 0,
        add = function (self, value)
            if self.length < self.maxlength then
                table.insert(self, value)
                self.pointer, self.length = self.pointer + 1, self.length + 1
            else
                self.pointer = self.pointer % self.maxlength + 1
                self[self.pointer] = value
            end
        end
    }
end


return UnorderedDeque
