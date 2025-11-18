-- Priority-based keymap dispatcher with fallback to original mapping.
-- It registers a single mapping per (mode, lhs) and runs handlers in order.
-- If none handle the key, the original key input is fed.

local M = {}

---@class fallback_map.Handler
---@field enabled? fun(): boolean
---@field run fun(): string|nil
---@field priority? integer

---@class fallback_map.Entry
---@field handlers fallback_map.Handler[]
---@field mapped boolean
---@field map_opts table

-- mode + lhs → fallback_map.Entry
local registry = {}
local seq = 0

local function key(mode, lhs, buffer)
  return table.concat({ mode, lhs, buffer or '' }, '\0')
end

local function termcodes(lhs)
  return vim.api.nvim_replace_termcodes(lhs, true, true, true)
end

local function normalize_opts(map_opts)
  local opts = map_opts and vim.tbl_extend('force', {}, map_opts) or {}
  if opts.buffer == true then
    opts.buffer = vim.api.nvim_get_current_buf()
  end
  return opts
end

local function delete_mapping(mode, lhs, opts)
  if opts and opts.buffer then
    pcall(vim.keymap.del, mode, lhs, { buffer = opts.buffer })
    return
  end

  pcall(vim.keymap.del, mode, lhs)
end

local function ensure_map(mode, lhs, buffer)
  local k = key(mode, lhs, buffer)
  local entry = registry[k]
  if not entry then
    return
  end

  delete_mapping(mode, lhs, entry.map_opts)

  entry.mapped = true
  local opts = vim.tbl_extend('force', entry.map_opts or {}, {
    expr = true,
    silent = entry.map_opts and entry.map_opts.silent == false and false or true,
  })

  vim.keymap.set(mode, lhs, function()
    return M._dispatch(mode, lhs, buffer)
  end, opts)
end

local function feed_original(mode, lhs, buffer)
  local k = key(mode, lhs, buffer)
  local entry = registry[k]
  if entry and entry.mapped then
    entry.mapped = false
    delete_mapping(mode, lhs, entry.map_opts)
  end

  local feed_mode = mode == 'i' and 'im' or 'n'
  vim.api.nvim_feedkeys(termcodes(lhs), feed_mode, false)

  if entry then
    ensure_map(mode, lhs, buffer)
  end

  return ''
end

local function sort_handlers(handlers)
  table.sort(handlers, function(a, b)
    local ap, bp = a.priority or 0, b.priority or 0
    if ap == bp then
      return (a.__seq or 0) < (b.__seq or 0)
    end
    return ap > bp
  end)
end

---Register fallback-aware mapping.
---@param modes string|string[]
---@param lhs string
---@param handler fallback_map.Handler
---@param map_opts? table
function M.register(modes, lhs, handler, map_opts)
  modes = type(modes) == 'table' and modes or { modes }
  for _, mode in ipairs(modes) do
    local opts = normalize_opts(map_opts)
    local k = key(mode, lhs, opts.buffer)

    registry[k] = registry[k] or { handlers = {}, mapped = false, map_opts = opts }
    if map_opts then
      registry[k].map_opts = opts
    end

    if type(handler) ~= 'table' then
      error('handler must be a table')
    end

    seq = seq + 1
    local h = vim.tbl_extend('force', { __seq = seq }, handler)

    table.insert(registry[k].handlers, h)
    sort_handlers(registry[k].handlers)
    ensure_map(mode, lhs, opts.buffer)
  end
end

---Dispatch registered handlers.
---@param mode string
---@param lhs string
---@param buffer? integer
---@return string
function M._dispatch(mode, lhs, buffer)
  local entry = registry[key(mode, lhs, buffer)]
  if not entry then
    return termcodes(lhs)
  end

  for _, h in ipairs(entry.handlers) do
    if not h.enabled or h.enabled() then
      local r = h.run()
      if r ~= nil then
        return r
      end
    end
  end

  return feed_original(mode, lhs, buffer)
end

return M
