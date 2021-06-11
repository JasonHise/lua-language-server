local files    = require 'files'
local vm       = require 'vm'
local lang     = require 'language'
local config   = require 'config'
local guide    = require 'parser.guide'

local requireLike = {
    ['include'] = true,
    ['import']  = true,
    ['require'] = true,
    ['load']    = true,
}

return function (uri, callback)
    local ast = files.getState(uri)
    if not ast then
        return
    end

    -- 遍历全局变量，检查所有没有 set 模式的全局变量
    guide.eachSourceType(ast.ast, 'getglobal', function (src)
        local key = src[1]
        if not key then
            return
        end
        if config.config.diagnostics.globals[key] then
            return
        end
        if config.config.runtime.special[key] then
            return
        end
        local node = src.node
        if node.tag ~= '_ENV' then
            return
        end
        if #vm.getDefs(src) == 0 then
            local message = lang.script('DIAG_UNDEF_GLOBAL', key)
            if requireLike[key:lower()] then
                message = ('%s(%s)'):format(message, lang.script('DIAG_REQUIRE_LIKE', key))
            end
            callback {
                start   = src.start,
                finish  = src.finish,
                message = message,
            }
            return
        end
    end)
end
