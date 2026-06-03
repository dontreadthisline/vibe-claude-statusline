# Claude Code Statusline

动态状态栏，展示系统资源、会话信息、编辑指示器和提供商余额。

支持 Linux 和 macOS。

## 快速安装

```bash
git clone https://github.com/your-repo/vibe-claude-statusline.git
cd vibe-claude-statusline
./install.sh
```

安装脚本会：
1. 检查依赖（jq、curl、bash）
2. 检测并自动安装 Nerd Font
3. 将脚本部署到 `~/.claude/`
4. 自动合并配置到 `settings.json`

## 依赖

### 强依赖
| 依赖 | 用途 | 安装 |
|------|------|------|
| `jq` | JSON 解析 | `brew install jq` |
| `curl` | HTTP 请求 | 系统自带 |
| `bash` | 脚本执行 | 系统自带 |
| **Nerd Font** | 图标渲染 | 安装脚本自动安装 |

### 可选依赖
| 依赖 | 用途 | 安装 |
|------|------|------|
| `git` | 分支/脏状态显示 | 系统自带或 Xcode |
| `nvidia-smi` | GPU 状态 | NVIDIA 驱动 |
| `osx-cpu-temp` | CPU 温度 (macOS) | `brew install osx-cpu-temp` |
| `sensors` | CPU 温度 (Linux) | `apt install lm-sensors` |

## 文件

| 文件 | 用途 |
|------|------|
| `install.sh` | 自动安装脚本 |
| `statusline-command.sh` | 状态栏主脚本，渲染所有 segment |
| `edit-hook.sh` | PostToolUse hook，记录当前编辑的文件 |
| `balance-fetch.sh` | 拉取提供商余额并缓存 |
| `settings-snippet.json` | settings.json 配置片段 |

## 环境变量

### 余额查询（可选）

```bash
# DeepSeek
export DEEPSEEK_API_KEY=sk-xxx

# DIDI LLM Proxy (滴滴内部)
export DIDI_API_KEY=sk-xxx
```

设置后状态栏会显示 `已用/总额` 格式的余额信息。

## 状态栏 Segments

```
 user@host   cwd  (branch)[!]   model[think]  ██░░░ 55%/200K  575/10000   1h40m   2%/43°C   0%/36°   3%/37°   11G/62G   4.0K;220G/938G   29K  0   23:30   (Edit) file.sh
```

从左到右：用户/主机、当前目录、git 分支/脏标记、模型名/thinking、上下文窗口使用(色条+百分比/总量)、成本/余额、会话时长、CPU使用/温度、GPU使用/温度、内存、磁盘、网络下行/上行、动态时钟图标+时间、最近编辑的文件(5s 后消失)。

![statusline screenshot](statusline-screenshot.png)

## 功能说明

### 动态时钟图标

使用 Nerd Font MDI `clock-time-X` 图标 (U+F1445~U+F1450)，最近整点四舍五入，12 小时制。

### 编辑指示器

- 绿色（Edit）、黄色（Write）、红色（删除类 Bash 命令）
- 显示 5 秒后自动消失
- 仅实际文件操作触发，无关命令不干扰
- 按 session_id 隔离，不会跨 Claude Code 实例串扰

### 余额显示

支持以下提供商：

| 提供商 | 触发条件 | 显示格式 |
|--------|---------|---------|
| DeepSeek | 设置 `DEEPSEEK_API_KEY` | `cost/balance` |
| DIDI Proxy | `ANTHROPIC_BASE_URL` 包含 `llm-proxy.intra.xiaojukeji` | `spend/total_budget` |

- 缓存 5 分钟，后台异步刷新
- 首次有花费时同步获取

## 扩展余额提供商

在 `balance-fetch.sh` 中添加：

```bash
get_xxx_balance() {
    local key="${XXX_API_KEY:-}"
    [ -z "$key" ] && return 1
    # 拉取逻辑
    echo "xxx|USD|spend|total"  # 或 "xxx|USD|balance"
}

# 在 provider 判断中添加
case "$model" in
    xxx*) provider="xxx" ;;
esac

case "$provider" in
    deepseek) get_deepseek_balance ;;
    didi)     get_didi_balance ;;
    xxx)      get_xxx_balance ;;
esac
```

## 手动安装

如果不想用安装脚本：

```bash
cp statusline-command.sh balance-fetch.sh edit-hook.sh ~/.claude/
chmod +x ~/.claude/*.sh
```

然后将 `settings-snippet.json` 的内容合并到 `~/.claude/settings.json`。

## 字体配置

安装 Nerd Font 后，在终端设置中选择对应字体：
- **iTerm2**: Preferences → Profiles → Text → Font
- **Terminal.app**: Preferences → Profiles → Font
- **VS Code**: 设置 `terminal.integrated.fontFamily`

推荐字体：`Hack Nerd Font`、`JetBrainsMono Nerd Font`、`FiraCode Nerd Font`
