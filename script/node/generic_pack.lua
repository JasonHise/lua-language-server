---@class Node.GenericPack: Class.Base
---@overload fun(generics?: Node.Generic[]): Node.GenericPack
local M = Class 'Node.GenericPack'

---@param generics? Node.Generic[]
function M:__init(generics)
    self.generics = generics or {}
    ---@type table<Node.Generic, Node>
    self.refMap = {}

    for _, generic in ipairs(self.generics) do
        self.refMap[generic] = generic
    end
end

---@param generic Node.Generic
---@param keepGeneric? boolean
---@return Node?
function M:getGeneric(generic, keepGeneric)
    local v = self.refMap[generic]
    if not v then
        return nil
    end
    if not keepGeneric and v.kind == 'generic' then
        ---@cast v Node.Generic
        return v.extends
    end
    return v
end

---@type Node.GenericPack?
M.basePack = nil

---@param pack Node.GenericPack | table<Node.Generic, Node>
---@param keepGeneric? boolean
---@return Node.GenericPack
function M:resolve(pack, keepGeneric)
    if pack.basePack == self then
        return pack
    end
    local new = ls.node.genericPack(self.generics)
    for k in pairs(self.refMap) do
        new.refMap[k] = pack[k]
                      or (not keepGeneric and ls.node.UNKNOWN)
    end
    new.basePack = self
    return new
end

---@param self Node.GenericPack
---@return boolean
---@return true
M.__getter.allResolved = function (self)
    for _, generic in ipairs(self.generics) do
        local value = self.refMap[generic]
        if not value or value.kind == 'generic' then
            return false, true
        end
    end
    return true, true
end

---@param skipLevel? integer
---@return string
function M:view(skipLevel)
    local views = {}
    for i, generic in ipairs(self.generics) do
        local node = self.refMap[generic]
        if not node then
            views[i] = generic.name
            goto continue
        end
        if node.kind ~= 'generic' then
            views[i] = node:view(skipLevel)
            goto continue
        end
        ---@cast node Node.Generic
        if node.extends then
            views[i] = string.format('%s:%s', node.name, node.extends:view(skipLevel))
        else
            views[i] = node.name
        end
        ::continue::
    end
    return string.format('<%s>', table.concat(views, ', '))
end

---@param generics? Node.Generic[]
---@return Node.GenericPack
function ls.node.genericPack(generics)
    return New 'Node.GenericPack' (generics)
end
