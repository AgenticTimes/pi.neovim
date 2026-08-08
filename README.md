# pi.nvim

Neovim 前端 for [Pi coding agent](https://pi.dev)。零第三方运行时依赖。

参考：Emacs 前端 `pi-coding-agent`（JSON-over-stdio RPC）与 `opencode.nvim`（大号居中 float 交互）。

## 需求

- Neovim ≥ 0.10
- pi CLI ≥ 0.84（`@earendil-works/pi-coding-agent`），在 PATH 中

## 测试

```bash
nvim --headless -u NONE -i NONE -l tests/run.lua
```
