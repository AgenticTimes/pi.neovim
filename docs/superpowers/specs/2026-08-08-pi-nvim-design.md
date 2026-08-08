# pi.nvim — Neovim 前端 for Pi coding agent：设计文档

- 日期：2026-08-08
- 状态：已获用户批准（§1 架构、§2 UI/测试/集成）
- 范围：Scope B（MVP + 增强）

## 1. 目标

为 [Pi](https://pi.dev)（`@earendil-works/pi-coding-agent` CLI）实现一个 Neovim 前端插件 `pi.nvim`，
参考两个现有项目：

- **Emacs 前端**（`pi-coding-agent`，本工作区同级仓库）：通信骨架——spawn `pi --mode rpc`，
  JSON-over-stdio 协议。已确认该协议（见 §3）。
- **opencode.nvim**（`nickjvandyke/opencode.nvim`）：交互模式——可 toggle 的大号居中 float、
  命令集、上下文注入、编辑同步、事件 autocmd。

**核心组合**：Emacs 前端的通信骨架 + opencode.nvim 的交互皮。

> 注意：pi 没有 HTTP/SSE server 模式（opencode 有 `--port`，pi 没有）。pi 官方的嵌入接口是
> `pi --mode rpc`（JSON stdin/stdout），`rpc-mode.d.ts` 明确标注 "Headless operation with
> JSON stdin/stdout protocol. Used for embedding the agent in other applications."。
> 因此插件必须自己 spawn 并托管 `pi` 进程，这一点已与用户确认。

## 2. 环境与依赖

- Neovim ≥ 0.10（使用内置 `vim.fn.jobstart`、`vim.json`、`vim.treesitter`，**零第三方运行时依赖**）
- `pi` CLI ≥ 0.84，在 PATH 中
- 可选：treesitter markdown grammar（有则高亮，无则退回基础配色，不强制）
- 目标用户环境：lazy.nvim、Leader 为 `,`、which-key/legendary 键位发现

## 3. RPC 协议（client 层契约）

### 启动

```
pi --mode rpc   # cwd = 当前项目目录（vim.fn.jobstart 的 cwd 选项）
```

### 命令（client → pi，每行一个 JSON 对象，带可选 id）

Scope B 用到的子集：

| 命令 | 参数 | 用途 |
| --- | --- | --- |
| `prompt` | message, streamingBehavior: "steer"\|"followUp" | 发送主 prompt；busy 时 followUp 排队 |
| `steer` | message | 当前工具结束后打断式指导 |
| `follow_up` | message | 显式排队 |
| `abort` | — | 中止当前回复/压缩 |
| `new_session` | parentSession? | 新会话 |
| `switch_session` | sessionPath | 切换会话 |
| `get_state` | — | 全量状态（model/thinking/messages/…） |
| `set_model` / `cycle_model` / `get_available_models` | provider, modelId | 模型切换/枚举 |
| `set_thinking_level` / `cycle_thinking_level` / `get_available_thinking_levels` | level | 思考级别 |
| `compact` | customInstructions? | 手动压缩上下文 |
| `set_auto_compaction` / `set_auto_retry` | enabled | 自动压缩/自动重试开关 |
| `get_messages` | — | 拉取消息历史 |
| `get_commands` | — | slash 命令枚举（extension/prompt/skill） |
| `get_session_stats` | — | 会话统计（token/成本）；header 成本显示为可选增强，不阻塞 |

### 响应

```
{"type":"response","id":…,"command":…,"success":bool,"data":…,"error":…}
```

按 id 关联到 pending request；无 id 时按 command 匹配（对齐 Emacs 前端的兜底逻辑）。

### 事件（pi → client，流式）

`agent_start/end`、`message_start/end`、`tool_execution_start/update/end`、
`compaction_start/end`、`auto_retry_start/end`、`extension_error`。

### 状态机（session 层）

`idle / sending / streaming / compacting`，迁移对齐 Emacs 前端 `pi-coding-agent--update-state-from-event`：

- `idle|sending → streaming`：`agent_start`
- `streaming → sending`：`agent_end` 且 willRetry
- `streaming → idle`：`agent_end` 无 retry
- `* → compacting`：`compaction_start`；`compaction_end` 按 willRetry/成功与否回到 sending/idle
- 本地命令在首个事件到达前可先置 busy（prompt 提交、手动压缩的 pre-event 窗口）

### 协议实现要点

- JSON 行 framing 用 chunk 累积（Emacs 前端 `accumulate-line-chunks` 同款），避免大响应
  （如 `get_messages`）反复 concat 造成 O(n²)
- 请求 id 自增；pending 表存 callback；响应/事件走 `on_stdout` 分发
- stderr 单独收集，用于启动失败诊断
- 超时（默认 30s）、进程退出处理（区分用户 abort 与异常崩溃，异常时展示 stderr 尾部 + 可重启）

## 4. 模块结构

```
pi.nvim/
├── lua/pi/
│   ├── init.lua          # 入口：setup(opts)、命令、公共 API（pi.on / pi.toggle）
│   ├── config.lua        # 默认配置 + 用户 opts 合并
│   ├── client.lua        # RPC 层（见 §3）
│   ├── session.lua       # 状态机 + 状态访问器（model/thinking/status/messages/active-tools）
│   ├── render.lua        # 聊天渲染（见 §5）
│   ├── ui.lua            # float 生命周期与三段式布局（见 §5）
│   ├── input.lua         # 输入区：发送/steer/abort/历史/补全（见 §5）
│   ├── context.lua       # 占位符展开 @this/@buffer/@buffers/@diagnostics/@visible
│   ├── edits.lua         # 文件写入检测 → buffer reload + :PiDiff
│   └── events.lua        # User PiEvent autocmd + pi.on(type, cb) API
├── plugin/pi.lua         # 插件入口：命令（Pi/PiToggle/PiDiff…）、autocmd、惰性加载
├── lua/pi/health.lua     # :checkhealth pi
├── doc/pi.nvim.txt       # help 文档
├── tests/                # 见 §8
├── README.md             # 中文安装/使用说明，含 lazy.nvim spec
└── LICENSE               # MIT
```

各模块单一职责、通过明确接口通信，可独立测试：

- `client` 不知道 UI；`session` 不知道渲染；`render` 只消费 `session` 状态 + 事件。

## 5. UI 设计

### 窗口

- 大号居中 float：默认 `width = 0.85 * columns`、`height = 0.85 * lines`，圆角边框（`rounded`），
  居中定位（对齐用户现有 opencode float 的 85%/85% 习惯）
- `,pi` 或 `:Pi` toggle；关闭不杀进程，聊天状态保留，重开秒回
- float 打开时若 focus 在输入区，进入 insert 态

### 三段式布局（照 pi TUI）

```
┌───────────────────────────────────────────────┐
│ 模型 │ 思考级别 │ 阶段 │ 会话名 │ 状态      ← header（1 行，状态行高亮组）
├───────────────────────────────────────────────┤
│                                               │
│  聊天区（~78%）                                │
│  · 消息节：角色头行 + markdown 渲染内容         │
│  · thinking 块：暗色、可折叠                   │
│  · 工具块：输出折叠成预览行、流式更新           │
│                                               │
├───────────────────────────────────────────────┤
│  输入区（~20%）：普通 buffer，insert 态         │
└───────────────────────────────────────────────┘
```

- **聊天区**是普通 buffer + markdown treesitter 高亮（无 grammar 时退回基础语法高亮）。
  消息节之间插分隔头行（`── 用户 · 14:32 ──`）；工具/思考块用 fold 实现折叠（`zc/zo`、`TAB`）。
  增量渲染：新内容 append，已渲染部分不动。
- **输入区**是普通 buffer，多行编辑、粘贴、历史（`M-p/M-n`）、清空（`<C-k>`）。

### 输入区键位（float 内局部映射，不污染全局）

| 键 | 动作 |
| --- | --- |
| `<CR>` | 发送（busy 时自动 followUp 排队） |
| `<C-s>` | steer |
| `<C-c>` | abort |
| `<C-k>` | 清空输入 |
| `M-p` / `M-n` | 历史导航 |
| `q`（float 内 normal 态）/ `<Esc>` | 退出 insert 回 normal；再次 `,pi` 或 `q` 关闭 float |

### 补全（输入区，手写，不依赖 nvim-cmp）

- `/` 触发 slash 命令补全：数据来自 `get_commands`（extension/prompt/skill 三类）
- `@` 触发文件引用补全（尊重 .gitignore，opencode.nvim/Emacs 前端同款体验）
- `<Tab>` 路径补全（`./` `../` `~/` 相对路径）

### Header 可点击字段（可选增强）

模型/思考级别字段允许点击（`mouse` 或键位）触发 cycle——列为 Nice-to-have，不阻塞 MVP。

## 6. 上下文注入（context.lua）

发送时在输入区展开占位符（opencode.nvim contexts 同款机制，可配置可扩展）：

| 占位符 | 内容 |
| --- | --- |
| `@this` | 选区；无选区则光标所在行 |
| `@buffer` | 当前 buffer 全文 |
| `@buffers` | 所有已打开 buffer |
| `@diagnostics` | 当前 buffer 诊断（选区限定，无选区全 buffer） |
| `@visible` | 当前窗口可见文本 |

config 支持自定义占位符（`contexts = { ["@file"] = function() … end }`）。

## 7. 编辑同步与事件（edits.lua / events.lua）

### 编辑同步

- 从 `tool_execution_start` 的 `args` 识别 `write`/`edit`/`apply_patch` 的目标文件路径
- 对应已打开的 buffer 自动 reload（比 `autoread` 精确：只刷被 pi 实际修改的文件）
- `:PiDiff`：对本轮 pi 触碰过的文件打开 `git diff` 清单（新文件/修改文件一目了然）
  （说明：pi 与 opencode 不同——pi 直接用 tool 写文件，没有"接受/拒绝"环节；故"接受/拒绝"
  调整为"自动 reload + diff 审查"，这是对 scope B 该项的忠实映射）

### PiEvent autocmd

- 每个 RPC 事件发 `User PiEvent`；事件内容经 `vim.g.pi_event` 传递（Neovim autocmd pattern
  不能携带 table，全局变量是标准做法）
- 提供编程 API：`require("pi").on("agent_start", function(event) … end)`

## 8. 错误处理

- pi 未安装/不在 PATH → `:checkhealth pi` 报错 + 启动时 notify（附安装提示 `npm i -g …`）
- 进程异常退出 → 展示 stderr 尾部，提供重启动作；用户主动 abort 不视为错误
- RPC 超时 → notify；JSON 解析失败 → 跳过该行 + debug log（`require("pi").log` 级别可控）
- `get_state` 返回错误（如未配置模型）→ 聊天区警告（对齐 Emacs 前端 `display-no-model-warning`）
- 所有 notify 走 `vim.notify`，可被 nvim-notify 接管

## 9. 测试方案

1. **fake pi**：`tests/fake_pi.lua` 用 `vim.fn.jobstart` 起一个伪装 RPC server 的进程
   （stdio 读 JSON 行、回响应、发事件），可脚本化驱动，headless 下跑通
   client → session → render 全链路（对齐 Emacs 前端 fake-pi 测试思路）
2. **单元测试**：line framing、请求关联/超时、状态机迁移、占位符展开——纯逻辑，headless 直接跑
3. **冒烟测试**：复用用户配置的套路——`nvim --headless -u init.lua -c "luafile tests/smoke.lua" -c "qa!"`
4. **真实集成**（手动，可选）：真 pi 跑一轮完整对话，验证流式渲染/折叠/编辑同步

## 10. 与用户 Neovim 配置的集成

- lazy.nvim spec 放入 `lua/plugins/ai.lua`（与 opencode 并列）：

  ```lua
  { dir = "~/source/pi/pi.nvim", cmd = { "Pi", "PiToggle", "PiDiff" }, lazy = true }
  ```

- 键位走 `lua/core/keymaps/` 的 `map()`（自动注册 LocalLeader + which-key 可见）：
  `,pi` toggle、`,mm` 模型 cycle、`,mt` 思考级别 cycle
- 冒烟测试并入现有 `scripts/smoke.lua` 风格

## 11. 明确不做（后续阶段）

fork/clone 会话树、`get_tree` 浏览、export HTML、extension UI 请求处理（`extension_ui_response`）、
`bash` 命令通道、`abort_bash`、会话重命名。这些的 RPC 命令已确认存在，架构预留位置即可。

## 12. 成功标准

1. `,pi` 打开大号居中 float，呈现 pi TUI 风格三段式布局
2. 完整对话可跑：发送（含 busy 排队）→ 流式渲染 → steer/abort → 模型/思考级别 cycle → 新会话
3. 工具/思考块可折叠；`@buffer`/`@diagnostics` 上下文注入生效
4. pi 改文件后对应 buffer 自动 reload；`:PiDiff` 展示改动
5. `User PiEvent` autocmd 与 `pi.on()` API 可用
6. 零第三方依赖；`tests/` 全部 headless 通过；README 含 lazy.nvim 安装示例
7. 已接入用户配置：`lua/plugins/ai.lua` + `lua/core/keymaps/`，冒烟测试并入
