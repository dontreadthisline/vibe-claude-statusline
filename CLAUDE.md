# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

Claude Code 动态状态栏，通过 shell 脚本渲染系统资源、会话信息和编辑指示器。三个脚本部署到 `~/.claude/`，由 Claude Code 的 `statusLine` 和 `PostToolUse` hooks 驱动。

## 文件与职责

| 文件 | 用途 |
|------|------|
| `statusline-command.sh` | 状态栏主脚本，通过 stdin 接收 JSON，输出 ANSI/Nerd Font 格式的状态行 |
| `edit-hook.sh` | PostToolUse hook，归类命令触发的文件操作（create/edit/delete），写入 session 级 temp file |
| `balance-fetch.sh` | 后台拉取 DeepSeek API 余额，写入 `/tmp/claude-balance-cache` |
| `settings-snippet.json` | 配置片段，合并到 `~/.claude/settings.json` |

## 架构

`statusline-command.sh` 是核心。Claude Code 每次渲染状态行时调用它，通过 stdin 传入 JSON（包含 model、context_window、cost、thinking、session_id、workspace.current_dir 等字段）。脚本从 JSON 中提取数据，采集系统指标（CPU/GPU/内存/磁盘/网络），拼接成彩色 segment 列表后 printf 输出。

`edit-hook.sh` 作为 PostToolUse hook 在每个 Write/Edit/NotebookEdit/Bash 工具调用后触发。它分析命令内容，提取被操作的文件路径和操作类别（create/edit/delete），写入 `/tmp/claude-status-edit-file-<session_id>`。主脚本读取该文件，若在 5 秒内则显示彩色编辑指示器。

`balance-fetch.sh` 由主脚本在余额缓存缺失或过期（>5 分钟）时后台触发。内部使用 lock file 防止并发，模型名决定查询哪个提供商（当前仅 DeepSeek）。

## 依赖

- **必须**: `jq`, `curl`, `bash`
- **可选**: `git`（分支/脏标记）、`nvidia-smi`（GPU 状态）、`sensors`（CPU 温度）、Nerd Font（图标渲染）

## 安装/测试

将三个 `.sh` 文件复制到 `~/.claude/`，将 `settings-snippet.json` 合并到 `~/.claude/settings.json`。需要设置 `DEEPSEEK_API_KEY` 环境变量才能显示余额。

手动测试主脚本：`echo '{"model":{"display_name":"test"},"workspace":{"current_dir":"/tmp"},"session_id":"test123"}' | bash statusline-command.sh`

### 扩展余额提供商

在 `balance-fetch.sh` 中添加 `get_xxx_balance()` 函数，输出格式 `provider|currency|total_balance`，然后在 case 分支中注册。主脚本自动读取缓存并显示 `cost/balance`。
