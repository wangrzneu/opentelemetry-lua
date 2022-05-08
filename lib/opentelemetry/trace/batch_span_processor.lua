local timer_at = ngx.timer.at
local now = ngx.now
local create_timer

local _M = {
}

local mt = {
    __index = _M
}

local function process_batches(premature, self, batches)
    if premature then
        return
    end

    for _, batch in ipairs(batches) do
        self.exporter:export_spans(batch)
    end
end

local function process_batches_timer(self, batches)
    local hdl, err = timer_at(0, process_batches, self, batches)
    if not hdl then
        ngx.log(ngx.ERR, "failed to create timer: ", err)
    end
end

local function flush_batches(premature, self)
    if premature then
        return
    end

    local delay

    -- batch timeout
    if now() - self.first_queue_t >= self.batch_timeout and #self.queue > 0 then
        table.insert(self.batch_to_process, self.queue)
        self.queue = {}
    end

    -- copy batch_to_process, avoid conflict with on_end
    local batch_to_process = self.batch_to_process
    self.batch_to_process = {}

    process_batches(nil, self, batch_to_process)

    -- check if we still have work to do
    if #self.batch_to_process > 0 then
        delay = 0
    elseif #self.queue > 0 then
        delay = self.inactive_timeout
    end

    if delay then
        create_timer(self, delay)
        return
    end

    self.is_timer_running = false
end

function create_timer(self, delay)
    local hdl, err = timer_at(delay, flush_batches, self)
    if not hdl then
        ngx.log(ngx.ERR, "failed to create timer: ", err)
        return
    end
    self.is_timer_running = true
end

------------------------------------------------------------------
-- create a batch span processor.
--
-- @exporter            opentelemetry.trace.exporter.oltp
-- @opts                [optional]
--                          opts.drop_on_queue_full: if true, drop span when queue is full, otherwise force process batches, default true
--                          opts.max_queue_size: maximum queue size to buffer spans for delayed processing, default 2048
--                          opts.batch_timeout: maximum duration for constructing a batch, default 5s
--                          opts.inactive_timeout: timer interval for processing batches, default 2s
--                          opts.max_export_batch_size: maximum number of spans to process in a single batch, default 256
-- @return              processor
------------------------------------------------------------------
function _M.new(exporter, opts)
    if not opts then
        opts = {}
    end

    local drop_on_queue_full = true
    if opts.drop_on_queue_full ~= nil and not opts.drop_on_queue_full then
        drop_on_queue_full = false
    end

    local self = {
        exporter = exporter,
        drop_on_queue_full = drop_on_queue_full,
        max_queue_size = opts.max_queue_size or 2048,
        batch_timeout = opts.batch_timeout or 5,
        inactive_timeout = opts.inactive_timeout or 2,
        max_export_batch_size = opts.max_export_batch_size or 256,
        queue = {},
        first_queue_t = 0,
        batch_to_process = {},
        is_timer_running = false,
        closed = false,
    }

    assert(self.batch_timeout > 0)
    assert(self.inactive_timeout > 0)
    assert(self.max_export_batch_size > 0)
    assert(self.max_queue_size > self.max_export_batch_size)

    return setmetatable(self, mt)
end

function _M.on_end(self, span)
    if not span.ctx:is_sampled() or self.closed then
        return
    end

    if #self.queue + #self.batch_to_process >= self.max_queue_size then
        -- drop span
        if self.drop_on_queue_full then
            ngx.log(ngx.WARN, "queue is full, drop span: trace_id = ", span.ctx.trace_id, " span_id = ", span.ctx.span_id)
            return
        end

        -- export spans
        process_batches_timer(self, self.batch_to_process)
        self.batch_to_process = {}
    end

    table.insert(self.queue, span)
    if #self.queue == 1 then
        self.first_queue_t = now()
    end

    if #self.queue >= self.max_export_batch_size then
        table.insert(self.batch_to_process, self.queue)
        self.queue = {}
    end

    if not self.is_timer_running then
        create_timer(self, self.inactive_timeout)
    end
end

function _M.force_flush(self)
    if self.closed then
        return
    end

    if #self.queue > 0 then
        table.insert(self.batch_to_process, self.queue)
        self.queue = {}
    end

    if #self.batch_to_process == 0 then
        return
    end

    process_batches_timer(self, self.batch_to_process)
    self.batch_to_process = {}
end

function _M.shutdown(self)
    self:force_flush()
    self.closed = true
end

return _M