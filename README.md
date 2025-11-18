# fallback-map.nvim

Priority-based keymap dispatcher with a simple handler chain. It runs registered handlers in order and, if none handle the key, simply feeds the raw `<lhs>` input (it does **not** restore a previous mapping).

## Features
- One mapping per `(mode, lhs)`; multiple handlers ordered by `priority` (desc).
- If no handler runs, the raw `<lhs>` input is sent (original mappings are **not** restored).
- Accepts `map_opts` (e.g., `buffer`, `noremap`) and always enforces `expr`/`silent`.

## Usage

```lua
-- lazy.nvim example
{
  'yuki-yano/fallback-map.nvim',
}

local fallback = require('fallback_map')

-- insx first
fallback.register('i', '<Tab>', {
  priority = 200,
  enabled = function()
    return #require('insx').detect('<Tab>') > 0
  end,
  run = function()
    local insx = require('insx')
    local keymap = require('insx.kit.Vim.Keymap')
    keymap.send(insx.expand('<Tab>'))
    return '' -- stop the chain
  end,
})

-- Copilot fallback
fallback.register('i', '<Tab>', {
  priority = 100,
  enabled = function()
    return require('copilot.suggestion').is_visible()
  end,
  run = function()
    require('copilot.suggestion').accept()
    return '' -- consume input
  end,
})
```

## API

```lua
fallback_map.register(modes, lhs, handler, map_opts)
```

- `modes`: string or array (e.g., `'i'` or `{ 'i', 'n' }`)
- `lhs`: key to map
- `handler`: `{ enabled?: fun(): boolean, run: fun(): string|nil, priority?: number }`
  - If `run` returns non-`nil`, the chain stops. Returning `nil` moves to the next handler.
- `map_opts`: passed to `vim.keymap.set`; `expr=true` and `silent=true` are enforced. `buffer` makes it buffer-local.

## Notes
- On first `register`, existing mappings for `<lhs>` are removed and replaced by fallback_map, and the original mapping is **not** reinstated.
- If no handler runs, the raw `<lhs>` is fed via `vim.api.nvim_feedkeys`.
- Handlers are executed in descending `priority`; ties keep insertion order.
- Buffer-local mappings are tracked per-buffer (`map_opts.buffer=true` resolves to the current buffer) and do not clobber global mappings.
