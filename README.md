# pi.neovim

[![CI](https://github.com/AgenticTimes/pi.neovim/actions/workflows/test.yml/badge.svg)](https://github.com/AgenticTimes/pi.neovim/actions/workflows/test.yml)

Neovim frontend for [Pi coding agent](https://pi.dev). Zero third-party runtime dependencies.

<p align="center">
  <img src="assets/usage.png" width="750" alt="pi.neovim usage"/>
</p>

## Two ways to use it

### `:Pi` — native pi TUI in a float terminal (default)

Runs the full native pi TUI in a centered rounded float (85% × 85%), the same pattern as
opencode terminal integrations. Colors, spinners, `/` command menu, skill completion — all
native pi.

**Show / hide with the shortcut key:**

1. Press the toggle key (default mapping below: `,ai`) → the float slides open with pi ready
2. Work inside the TUI as usual (type prompts, run `/` commands)
3. Hide it: press `,ai` again — or inside the float press `Ctrl-\ Ctrl-n` then `q`
4. Reopen any time with `,ai` — the pi process stays alive, so it's instant

> Closing the window does **not** kill the pi process; the session is preserved until you quit Neovim.

### `:PiChat` — custom chat UI (experimental)

JSON-over-stdio RPC: a markdown chat buffer + multi-line input buffer, with `@buffer` /
`@diagnostics` context injection, `User PiEvent` autocmds, buffer auto-reload on tool writes,
and `:PiDiff`.

**Show / hide:** `:PiChat` opens it, `:PiChat` again (or `q` in the input buffer) closes it.

## Requirements

- Neovim ≥ 0.10 (zero third-party runtime deps)
- pi CLI ≥ 0.84 (`@earendil-works/pi-coding-agent`), in `PATH`
- Optional: treesitter markdown grammar (markdown highlighting in the chat buffer)

## Install (lazy.nvim)

```lua
{
  "AgenticTimes/pi.neovim",
  lazy = true,
  cmd = { "Pi", "PiToggle", "PiChat", "PiNewSession", "PiCycleModel", "PiCycleThinking", "PiDiff" },
  config = function()
    require("pi").setup({})
  end,
}
```

## Usage

`:Pi` (or map `,ai`) opens the native pi TUI float. If you use nvim-cmp, disable it inside
the `pi://input` buffer (only relevant for `:PiChat`):

```lua
vim.api.nvim_create_autocmd("InsertEnter", {
  pattern = "pi://input",
  callback = function()
    local ok, cmp = pcall(require, "cmp")
    if ok and cmp.setup and cmp.setup.buffer then cmp.setup.buffer({ enabled = false }) end
  end,
})
```

Recommended global keymaps (Leader is `,`; avoid `,p` if you already map it to paste):

```lua
vim.keymap.set("n", "<Leader>ai", function() require("pi").toggle() end, { desc = "pi: toggle TUI float" })
vim.keymap.set("n", "<Leader>am", function() require("pi").cycle_model() end, { desc = "pi: cycle model" })
vim.keymap.set("n", "<Leader>at", function() require("pi").cycle_thinking_level() end, { desc = "pi: cycle thinking" })
```

Commands: `:Pi` / `:PiToggle` (toggle TUI float), `:PiChat` (custom chat UI),
`:PiNewSession`, `:PiCycleModel`, `:PiCycleThinking`, `:PiDiff` (diff of files touched this session).

## :PiChat input keymaps (buffer-local)

| Key | Action |
| --- | --- |
| `<CR>` | Send (queues as follow-up while busy) |
| `<C-s>` | Steer (interrupts after current tool) |
| `<C-c>` | Abort |
| `<C-k>` | Clear input |
| `M-p` / `M-n` | History |
| `<Tab>` | Complete (`/` commands, `@` file refs, paths) |
| `q` | Close float |

## Context placeholders (:PiChat)

Expanded at send time:

| Placeholder | Content |
| --- | --- |
| `@this` | Selection, or current line |
| `@buffer` | Full current buffer |
| `@buffers` | All loaded buffers |
| `@diagnostics` | Current buffer diagnostics |
| `@visible` | Visible window text |

Custom: `require("pi").setup({ contexts = { ["@file"] = function() return "..." end } })`.

## Events

Every RPC event fires a `User PiEvent` autocmd (`vim.g.pi_event` carries the event); or use
the API:

```lua
require("pi").on("agent_start", function(event) end)
require("pi").on("*", function(event) end) -- all events
```

## Options

```lua
require("pi").setup({
  executable = "pi",                       -- pi CLI command or {cmd, arg...}
  window = { width = 0.85, height = 0.85, border = "rounded" },
  keys = { send = "<CR>", steer = "<C-s>", abort = "<C-c>", clear = "<C-k>",
           history_prev = "<M-p>", history_next = "<M-n>", close = "q", complete = "<Tab>" },
  rpc_timeout = 30,                        -- seconds
  warm_start = false,                      -- preload pi in background for instant first open
  warm_start_delay = 2000,                 -- warm-up delay (ms)
  contexts = {},                           -- custom context placeholders
})
```

## Edit sync (:PiChat)

When pi writes files via tools, open unmodified buffers reload automatically; `:PiDiff`
opens a git diff of the files pi touched this session.

## Known limitations

- `@` file completion relies on `git ls-files` (no candidates outside a git repo).
- Session-tree browsing / fork / clone / export HTML / extension UI requests / the `bash`
  RPC channel are not implemented yet (RPC surface confirmed, architecture reserved).

## Testing

```bash
nvim --headless -u NONE -i NONE -l tests/run.lua     # full suite
nvim --headless -u NONE -i NONE -l tests/smoke.lua   # smoke
```

Tests use `tests/fake_pi.mjs` (Node) as a pi RPC double, exercising the full
client → session → render pipeline headlessly.
