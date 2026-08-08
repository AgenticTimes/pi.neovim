# pi.nvim

Neovim 前端 for [Pi coding agent](https://pi.dev)。零第三方运行时依赖。

参考：Emacs 前端 `pi-coding-agent`（JSON-over-stdio RPC 通信骨架）与 `opencode.nvim`（大号居中 float 交互模式）。

## 需求

- Neovim ≥ 0.10（零第三方运行时依赖）
- pi CLI ≥ 0.84（`@earendil-works/pi-coding-agent`），在 PATH 中
- 可选：treesitter markdown grammar（有则聊天区 markdown 高亮，无则退回基础渲染）

## 安装（lazy.nvim）

```lua
{
  dir = "~/source/pi/pi.nvim",
  lazy = true,
  cmd = { "Pi", "PiToggle", "PiNewSession", "PiCycleModel", "PiCycleThinking", "PiDiff" },
  config = function()
    require("pi").setup({})
  end,
}
```

## 快速开始

`:Pi`（或 `,pi`）打开居中的大号 float：顶部状态栏（winbar：模型 | 思考级别 | 阶段 | 会话名）、
中间聊天区（markdown 渲染 + 工具块可折叠）、底部输入区。

首次打开会 spawn `pi --mode rpc`（cwd = 当前项目目录）并拉取会话状态。关闭 float 不杀进程，
聊天内容保留，重开秒回。

## 键位

float 内输入区（buffer-local）：

| 键 | 动作 |
| --- | --- |
| `<CR>` | 发送（busy 时自动 follow-up 排队） |
| `<C-s>` | steer（当前工具结束后打断） |
| `<C-c>` | abort |
| `<C-k>` | 清空输入 |
| `M-p` / `M-n` | 历史导航 |
| `<Tab>` | 补全（`/` slash 命令、`@` 文件引用、路径） |
| `q` | 关闭 float |

建议的用户侧键位（`<Leader>=,`）：

```lua
local map = require("core.keymaps.util").map
map("n", "<Leader>pi", function() require("pi").toggle() end, { desc = "pi: toggle float" })
map("n", "<Leader>mm", function() require("pi").cycle_model() end, { desc = "pi: cycle model" })
map("n", "<Leader>mt", function() require("pi").cycle_thinking_level() end, { desc = "pi: cycle thinking" })
```

命令：`:Pi` / `:PiToggle`（开关）、`:PiNewSession`、`:PiCycleModel`、`:PiCycleThinking`、`:PiDiff`（本轮改动 diff）。

## 上下文占位符

发送时在输入区展开：

| 占位符 | 内容 |
| --- | --- |
| `@this` | 选区；无选区则光标所在行 |
| `@buffer` | 当前 buffer 全文 |
| `@buffers` | 所有已打开 buffer |
| `@diagnostics` | 当前 buffer 诊断 |
| `@visible` | 当前窗口可见文本 |

自定义：`require("pi").setup({ contexts = { ["@file"] = function() return "..." end } })`。

## 事件

每个 RPC 事件触发 `User PiEvent` autocmd，事件内容在 `vim.g.pi_event`；也可用编程 API：

```lua
require("pi").on("agent_start", function(event) end)
require("pi").on("*", function(event) end) -- 所有事件
```

## 配置项

```lua
require("pi").setup({
  executable = "pi",                       -- pi CLI 命令名或 {cmd, arg...}
  window = { width = 0.85, height = 0.85, border = "rounded" },
  keys = { send = "<CR>", steer = "<C-s>", abort = "<C-c>", clear = "<C-k>",
           history_prev = "<M-p>", history_next = "<M-n>", close = "q", complete = "<Tab>" },
  rpc_timeout = 30,                        -- 秒
  contexts = {},                           -- 自定义上下文占位符
})
```

## 编辑同步

pi 用 tool 写文件时，对应已打开的 buffer 自动 reload（未修改的才刷）；`:PiDiff` 打开本轮
pi 触碰文件的 `git diff` 清单。

## 已知限制

- 补全的 `@` 文件引用依赖 `git ls-files`（非 git 仓库无候选）；`<Tab>` 若被 nvim-cmp 抢占，
  可在 `pi://input` buffer 上禁用 cmp。
- 会话树浏览 / fork / clone / export HTML / extension UI 请求 / `bash` 命令通道：暂未实现
  （RPC 命令面已确认存在，架构预留）。

## 测试

```bash
nvim --headless -u NONE -i NONE -l tests/run.lua     # 全量测试
nvim --headless -u NONE -i NONE -l tests/smoke.lua   # 冒烟
```

测试用 `tests/fake_pi.mjs`（Node）伪装 pi RPC server，headless 跑通 client → session → render 全链路。
