---@class VM.Runner
local M = Class 'VM.Runner'

---@type 'ready' | 'running' | 'finished'
M.state = 'ready'

---@class VM.Runner.Context
---@field lastClass? Node.Type
---@field generics? table<LuaParser.Node.CatGeneric, Node.Generic>
---@field catGroup? LuaParser.Node.Cat[]
---@field catGroupMap? table<LuaParser.Node.Cat, LuaParser.Node.Cat[]>

---@param block LuaParser.Node.Block
---@param scope Scope
function M:__init(block, scope)
    self.block = block
    self.scope = scope
    self.node  = scope.node
    ---@type table<LuaParser.Node.Base, Node?>
    self.nodeMap = {}
    ---@type table<LuaParser.Node.Base, Node.Variable?>
    self.variableMap = {}
    ---@type VM.Runner.Context
    self.context = {}
    ---@type function[]
    self.disposes = {}
    self.resolve = function (unsolve, source)
        return self:parse(source)
    end
end

function M:__del()
    for _, dispose in ipairs(self.disposes) do
        dispose()
    end
end

---@param dispose function
function M:addDispose(dispose)
    self.disposes[#self.disposes+1] = dispose
end

function M:run()
    if self.state ~= 'ready' then
        return
    end
    self.state = 'running'
    for _, state in ipairs(self.block.childs) do
        self:parse(state)
    end
    self.state = 'finished'
end

---@param source LuaParser.Node.Base
---@return Node
function M:parse(source)
    local node = self.nodeMap[source]
    if node then
        return node
    end
    self.nodeMap[source] = self.node.UNKNOWN
    local parser = M.parsers[source.kind]
    if not parser then
        return self.node.UNKNOWN
    end
    node = parser(self, source)
    if not node then
        return self.node.UNKNOWN
    end
    self.nodeMap[source] = node
    return node
end

---@param source LuaParser.Node.Base
---@return Node.Location
function M:makeLocation(source)
    return {
        uri = self.scope.uri,
        offset = source.start,
        length = source.finish - source.start,
    }
end


---@param field LuaParser.Node.Term
---@return Node.Key
function M:getKey(field)
    if field.kind == 'field' then
        ---@cast field LuaParser.Node.Field
        local key = field.key
        if key.kind == 'fieldid' then
            ---@cast key LuaParser.Node.FieldID
            return key.id
        else
            ---@cast key LuaParser.Node.Exp
            if key.isLiteral then
                ---@cast key LuaParser.Node.Literal
                return key.value or self.scope.node.UNKNOWN
            end
            return self.scope.node.UNKNOWN
        end
    elseif field.kind == 'var' then
        ---@cast field LuaParser.Node.Var
        return field.id
    else
        return self.scope.node.UNKNOWN
    end
end

---@param field LuaParser.Node.Field
---@return Node.Key[]
function M:getFullPath(field)
    local path = {}

    local current = field.last
    for _ = 1, 1000 do
        if not current then
            break
        end
        path[#path+1] = self:getKey(current)
        if current.kind == 'var' then
            break
        end
        current = current.last
    end

    ls.util.revertArray(path)

    return path
end

---@param field LuaParser.Node.Field
---@return LuaParser.Node.Var?
function M:getFirstVar(field)
    local current = field.last
    for _ = 1, 1000 do
        if not current then
            return nil
        end
        if current.kind == 'var' then
            ---@cast current LuaParser.Node.Var
            return current
        end
        current = current.last
    end
end

---@param source LuaParser.Node.Base
---@param key Node.Key
---@param value? LuaParser.Node.Exp
---@param useType? boolean
---@return Node.Field
function M:makeNodeField(source, key, value, useType)
    local node = self.scope.node
    ---@type Node
    local nkey
    if type(key) ~= 'table' then
        ---@cast key -Node
        nkey = node.value(key)
    else
        ---@cast key Node
        nkey = key
    end
    local nvalue
    if not value or value.kind == 'nil' then
        nvalue = node.NIL
    elseif value.isLiteral then
        ---@cast value LuaParser.Node.Literal
        nvalue = node.value(value.value)
        if useType then
            nvalue = node.type(nvalue.typeName)
        end
    else
        nvalue = self:unsolve(node.UNKNOWN, value)
    end
    local field = {
        key = nkey,
        value = nvalue,
        location = self:makeLocation(source),
    }
    return field
end

---@param baseNode Node
---@param source? LuaParser.Node.Base
---@return Node
function M:unsolve(baseNode, source)
    if not source then
        return baseNode
    end
    return self.node.unsolve(baseNode, source, self.resolve)
end

---@param generic LuaParser.Node.CatGeneric
---@return Node.Generic
function M:makeGeneric(generic)
    local generics = self.context.generics
    if not generics then
        generics = {}
        self.context.generics = generics
    end
    if generics[generic] then
        return generics[generic]
    end
    local gnode = self.node.generic(generic.id.id, generic.extends and self:parse(generic.extends))

    generics[generic] = gnode

    return gnode
end

function M:clearCatGroup()
    local context = self.context
    context.catGroup = nil
end

---@param group LuaParser.Node.Cat[]
---@param cat LuaParser.Node.Cat
---@return boolean
local function isNearby(group, cat)
    local last = group[#group]
    if not last then
        return true
    end
    return (last.finishRow + 1) == cat.startRow
end

---@param cat LuaParser.Node.Cat
---@param nearby? boolean
function M:addToCatGroup(cat, nearby)
    local context = self.context
    local group = context.catGroup

    if not group
    or (nearby and not isNearby(group, cat)) then
        group = {}
        context.catGroup = group
    end
    group[#group+1] = cat

    local map = context.catGroupMap
    if not map then
        map = {}
        context.catGroupMap = map
    end
    map[cat] = group
end

---@param nearbySource? LuaParser.Node.Base
---@return LuaParser.Node.Cat[]?
function M:getCatGroup(nearbySource)
    local group = self.context.catGroup
    if not group then
        return nil
    end
    local first = group[1]
    if not first then
        return nil
    end
    if nearbySource then
        local sourceLine = nearbySource.startRow
        local catLine = group[#group].finishRow
        if (sourceLine - 1) ~= catLine then
            return nil
        end
    end
    return group
end

---@param source LuaParser.Node.Base
---@param variable Node.Variable
function M:setVariable(source, variable)
    self.variableMap[source] = variable
end

---@param source LuaParser.Node.Base
---@return Node.Variable?
function M:getVariable(source)
    self:parse(source)
    return self.variableMap[source]
end

---@alias VM.RunnerParser fun(runner: VM.Runner, source: LuaParser.Node.Base): Node?

---@private
---@type table<string, VM.RunnerParser>
M.parsers = {}

---@param kind string
---@param parser VM.RunnerParser
function ls.vm.registerRunnerParser(kind, parser)
    M.parsers[kind] = parser
end

---@param block LuaParser.Node.Block
---@param scope Scope
---@return VM.Runner
function ls.vm.createRunner(block, scope)
    return New 'VM.Runner' (block, scope)
end
