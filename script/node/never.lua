---@class Node.Never: Node
---@operator bor(Node?): Node
---@operator shr(Node): boolean
---@overload fun(): Node.Never
local M = ls.node.register 'Node.Never'

M.kind = 'never'

M.typeName = 'never'

function M:view()
    return 'never'
end

function M:onCanCast(other)
    return false
end

function M:onCanBeCast(other)
    return false
end

ls.node.NEVER = New 'Node.Never' ()

function ls.node.never()
    return ls.node.NEVER
end
