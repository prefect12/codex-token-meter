# AI Token Meter + Task Bar

两个原生 macOS 状态栏工具，面向本机 Codex 和 Claude Code 工作流。

- **AI Token Meter**：查看 Codex / Claude Code 的本地 token 用量、缓存命中率、实时剩余额度、模型统计、仓库洞察和订阅价值估算。
- **Task Bar**：把正在运行、等待输入、已完成但未读的 Codex / Claude Code 任务集中到一个轻量状态栏列表里，方便快速回到任务。

两者都只读取本机数据，不上传会话日志。

## 截图

### AI Token Meter

<p align="center">
  <img src="docs/images/ai-token-meter-release.png" alt="AI Token Meter menu dashboard" width="420">
</p>

### Task Bar

<p align="center">
  <img src="docs/images/task-bar-release.png" alt="Task Bar popover" width="420">
</p>

## 当前版本

| App | Version | Build | Bundle |
| --- | --- | --- | --- |
| AI Token Meter | `0.2.3` | `17` | `/Applications/AI Token Meter.app` |
| Task Bar | `0.1.2` | `3` | `/Applications/Task Bar.app` |

## 数据来源

AI Token Meter 读取：

```text
~/.codex/sessions/**/rollout-*.jsonl
~/.codex/archived_sessions/rollout-*.jsonl
$CODEX_HOME/sessions/**/rollout-*.jsonl
$CODEX_HOME/archived_sessions/rollout-*.jsonl
~/.claude/projects/**/*.jsonl
~/Library/Application Support/Codex Token Meter/
```

Task Bar 读取：

```text
~/.codex/logs_2.sqlite
~/.codex/state_5.sqlite
~/.codex/sessions/**/rollout-*.jsonl
~/.claude/projects/**/*.jsonl
```

实时额度依赖本机 Codex runtime 的 `codex app-server`。Codex 服务状态 chip 会只读请求 `https://status.openai.com/api/v2/summary.json`。

## 功能概览

### AI Token Meter

- `All / Codex / Claude` 视图和 `24h / 7d / 30d` 窗口。
- 5 小时、周额度、剩余额度、重置时间和使用节奏。
- Codex + Claude token 汇总，包含 input、output、cached input、fresh input 和 total。
- 详情窗口包含概览、仓库洞察、日历、金额、模型、设置、诊断和关于页面。
- 本地聚合缓存：状态栏和详情窗口会先显示上次完整结果，再后台刷新。
- 订阅价值估算和 API 等价成本分开计算，不把 `reasoning_output_tokens` 重复计费。
- 支持 English、简体中文、繁体中文、日本語、Français、Deutsch、Español、한국어。

### Task Bar

- 在状态栏显示当前需要关注的任务数量。
- 按 `All / Running / Waiting / Done` 过滤任务。
- 合并 Codex app-server、Codex 本地 rollout、Claude Code JSONL 的任务状态。
- 支持运行中、等待输入、已完成未读、长时间运行等状态。
- 支持任务 hover 摘要、token 概览、滑动移除、设置页和分组顺序配置。
- 保持和 AI Token Meter 接近的深色 AppKit 视觉系统。

## 构建

要求：

- macOS 13 或更新版本
- Xcode Command Line Tools
- `swiftc`

构建 AI Token Meter：

```bash
./build.sh
```

构建 Task Bar：

```bash
./build_petbar.sh
```

## 安装

安装并启动 AI Token Meter：

```bash
./install.sh
```

安装并启动 Task Bar：

```bash
./install_petbar.sh
```

## 打包 DMG

打包 AI Token Meter：

```bash
./package_dmg.sh
```

输出：

```text
dist/AI-Token-Meter-0.2.3.dmg
```

打包 Task Bar：

```bash
./package_petbar_dmg.sh
```

输出：

```text
dist/Task-Bar-0.1.2.dmg
```

## 命令行检查

AI Token Meter：

```bash
"./build/AI Token Meter.app/Contents/MacOS/CodexTokenMeter" --print --window=week --quota=all
"./build/AI Token Meter.app/Contents/MacOS/CodexTokenMeter" --print-live
"./build/AI Token Meter.app/Contents/MacOS/CodexTokenMeter" --print-service-status
```

Task Bar：

```bash
"./build/Task Bar.app/Contents/MacOS/TaskBar" --print
```

渲染 README 截图：

```bash
"./build/AI Token Meter.app/Contents/MacOS/CodexTokenMeter" --render-dashboard=docs/images/ai-token-meter-release.png
"./build/Task Bar.app/Contents/MacOS/TaskBar" --render-taskbar=docs/images/task-bar-release.png
```

## 隐私

这个仓库不包含你的 Codex 日志、Claude Code 日志、token 数据、构建产物或 DMG。应用运行时只在本机读取日志和缓存；不会上传会话内容。为了兼容旧版本，AI Token Meter 继续使用 `~/Library/Application Support/Codex Token Meter/` 保存本地设置和派生缓存。
