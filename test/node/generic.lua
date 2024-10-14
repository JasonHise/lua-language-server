do
    local N = ls.node.generic('N', ls.node.NUMBER)
    local U = ls.node.generic 'U'
    local pack = ls.node.genericPack { N, U }
    local array = ls.node.array(N)
    local tuple = ls.node.tuple { N, U }
    local table = ls.node.table { [N] = U }
    local func  = ls.node.func()
        : addParam('a', N)
        : addVarargParam(U)
        : addReturn(nil, tuple)

    assert(N:view() == '<N:number>')
    assert(U:view() == '<U>')
    assert(pack:view() == '<N:number, U>')
    assert(array:view() == '<N:number>[]')
    assert(tuple:view() == '[<N:number>, <U>]')
    assert(func:view() == 'fun(a: <N:number>, ...: <U>):[<N:number>, <U>]')

    local newPack = pack:resolve {
        N = ls.node.type 'integer'
    }
    assert(newPack:view() == '<integer, unknown>')

    local newArray = array:resolveGeneric(newPack)
    assert(newArray:view() == 'integer[]')

    local newTuple = tuple:resolveGeneric(newPack)
    assert(newTuple:view() == '[integer, unknown]')

    local newTable = table:resolveGeneric(newPack)
    assert(newTable:view() == '{ [integer]: unknown }')

    local newFunc = func:resolveGeneric(newPack)
    assert(newFunc:view() == 'fun(a: integer, ...: unknown):[integer, unknown]')
end
