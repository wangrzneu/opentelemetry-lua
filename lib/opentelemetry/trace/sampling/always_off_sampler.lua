local result_new = require("opentelemetry.trace.sampling.result").new

local _M = {
}

local mt = {
    __index = _M
}

function _M.new()
    return setmetatable({}, mt)
end

function _M.should_sample(self, parameters)
    return result_new(0, parameters.parent_ctx.trace_state)
end

function _M.description(self)
    return "AlwaysOffSampler"
end

return _M