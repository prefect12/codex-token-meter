# Codex Token Meter

[English README](README.md)

Codex Token Meter 是一个原生 macOS 状态栏工具，用来查看本机 Codex 的 token 消耗、缓存命中率、实时剩余额度、模型级用量和订阅金额估算。

它直接读取本地 Codex 会话日志：

```text
~/.codex/sessions/**/rollout-*.jsonl
~/.codex/archived_sessions/rollout-*.jsonl
$CODEX_HOME/sessions/**/rollout-*.jsonl
$CODEX_HOME/archived_sessions/rollout-*.jsonl
```

在可用时，它还会通过本机 Codex 运行时读取实时限额信息，例如 5 小时窗口、周窗口、重置时间和剩余比例。

## 截图

### 状态栏面板

![Codex Token Meter 中文状态栏面板](docs/images/zh-menu-popover.png)

### 详情窗口

![Codex Token Meter 中文详情概览](docs/images/zh-details-overview.png)

### 金额页面

![Codex Token Meter 中文金额页面](docs/images/zh-details-costs.png)

### 日历页面

![Codex Token Meter 中文日历页面](docs/images/zh-details-calendar.png)

<details>
<summary>英文界面预览</summary>

![Codex Token Meter English menu bar dashboard](docs/images/en-menu-popover.png)

![Codex Token Meter English details overview](docs/images/en-details-overview.png)

![Codex Token Meter English cost and budget page](docs/images/en-details-costs.png)

</details>

## 功能

- 状态栏显示 5 小时剩余额度、周额度、当日 token 或 7 日 token。
- 弹窗支持 `24h / 7d / 30d` 时间窗口切换。
- 支持 `All / 模型限额 / Other` 视图，区分 Codex 总用量、当前识别到的模型级限额用量和非模型级限额用量。
- 显示 5 小时额度、周额度、缓存命中率三个实时圆环。
- 展示 input、output、cached input、fresh input 和 total token。
- 详情窗口包含概览、模型、日历、金额、诊断、设置和关于页面。
- 过去 365 天日历热力图，点击某一天可查看当天用量详情。
- 模型页面按模型聚合长期 token 用量。
- 金额页面支持月付金额、本周剩余预算、历史消耗、当日价值、API 等价成本、可选外部 API 成本和币种折算。
- 诊断页面展示 Codex CLI/auth 状态、实时额度可用性、日志覆盖、可选 API 成本输入和其他工具探测结果。
- 默认覆盖当前会话、归档会话，以及已设置 `$CODEX_HOME` 时对应的会话目录。
- 支持 English、简体中文、繁体中文、日本語、Français、Deutsch、Español、한국어。
- 数字单位会跟随界面语言：英文使用 `K / M / B`，中文使用 `万 / 亿`。
- 可配置 Codex 日志目录、状态栏显示内容、开机启动、低额度提醒、付款币种、展示币种和付费开始日期。
- 支持手动刷新、打开本地日志目录和命令行统计检查。

## 数据与计算口径

Codex Token Meter 使用本机数据源：

- **token 用量**：来自本地 Codex 会话日志。默认扫描 `~/.codex/sessions`、`~/.codex/archived_sessions`，以及设置了 `$CODEX_HOME` 时其中的 `sessions` / `archived_sessions` 目录。如果在设置里手动选择日志目录，该目录会覆盖默认扫描范围。应用扫描 `token_count` 事件，读取 `input_tokens`、`cached_input_tokens`、`output_tokens`、`reasoning_output_tokens` 和 `total_tokens`，再用相邻累计值的差值计算本次新增 token，并按小时、日期、会话和模型聚合。
- **实时额度比例**：来自本机 Codex 运行时。应用启动 `codex app-server`，调用 `account/rateLimits/read`，读取 5 小时窗口和周窗口的 `usedPercent`、`resetsAt` 等信息。状态栏和圆环里的剩余额度按 `100 - usedPercent` 显示。应用会从实时返回里学习当前非 Codex 的模型级限额窗口，不再只依赖历史 Spark ID。
- **缓存比例**：来自本地 token 明细，计算方式是 `cached_input_tokens / input_tokens * 100`。
- **金额估算**：不是官方账单。月付金额来自设置项，默认 `$200`；周预算按 `月付金额 * 12 / 52` 计算。本周已用金额优先使用实时周 `usedPercent` 换算，历史日期和历史周则按本地 token 用量、历史峰值和已记录的周额度比例估算。
- **API 等价成本**：这是另一套独立估算，用来回答“如果这些本地 Codex token 直接按 API token 计费，大约会花多少钱”。应用会按可识别模型分别计价 fresh input、cached input 和 output。当前内置价格使用 GPT-5.5、GPT-5.4、GPT-5.4 mini 的官方 API 单价，以及 GPT-5.3-Codex / GPT-5.2 风格 Codex 模型的 token-based Codex rate card 等价口径。`reasoning_output_tokens` 不会再次叠加，因为本地 `token_count` 事件里的 `total_tokens` 已经等于 input 加 output。无法识别模型标签的记录不会被强行估价，并会降低界面中的 priced-token 覆盖率。
- **外部 API 成本**：这是可选的本地 JSON 输入，用来补充不经过 Codex 日志的直接 OpenAI API 用量。默认读取 `~/Library/Application Support/Codex Token Meter/api-usage.json`。成本字段支持 `usd_value`、`total_usd`、`usd`、`cost_usd`，token 字段支持 `total_tokens`、`tokens`、`usage_tokens`。

外部 API 成本文件示例：

```json
{
  "usd": 12.34,
  "total_tokens": 123456,
  "updated_at": "2026-06-15T00:00:00Z"
}
```

如果一周内 OpenAI 重置或刷新了额度，实时周比例会按新的 `usedPercent` 更新，所以状态栏和周额度圆环可能会突然显示更多剩余额度。本地 token 日志不会被清零；金额页会记录观察到的周使用比例下降，并保留历史周见过的最大周使用比例，避免历史金额在重置后被当前低比例冲掉。这个处理仍然是本地观测估算，不等同于官方账单导出。

如果通过 Codex CLI 或 Codex app 使用 API 登录状态启动任务，只要 Codex 仍然写入本地 `rollout-*.jsonl` 日志，本地 token 用量就可以继续统计；实时额度比例取决于 `codex app-server` 是否能在当前认证方式下返回 `account/rateLimits/read`。如果直接调用 OpenAI API 而不经过本机 Codex 客户端，可以通过可选的本地 `api-usage.json` 表示；应用本身不会主动调用账单 API。

## 最近更新

- 新增按 rollout 文件的日级聚合缓存，`7d`、`30d` 和年度详情扫描可以复用聚合摘要，不再每次遍历缓存里的全部事件。
- 保留滚动 `24h` 窗口的事件级精确计算，同时加速自然日窗口和详情页预热扫描。
- 支持从旧版解析缓存迁移到新版聚合缓存，未变化的 JSONL 日志不需要重新读取。
- 提升状态栏弹窗的次级文字对比度，并为主要操作按钮加入 SF Symbol 图标。
- 为额度圆环、分段控件、设置输入框、下拉框和开关补充基础辅助功能标签。

## 隐私说明

这个项目只包含应用源码和静态资源，不包含你的 Codex 日志、token 消耗数据、截图、构建产物或 DMG。

应用运行时会读取：

```text
~/.codex/sessions
~/.codex/archived_sessions
$CODEX_HOME/sessions
$CODEX_HOME/archived_sessions
~/Library/Application Support/Codex Token Meter/ParsedRollouts
~/Library/Application Support/Codex Token Meter/api-usage.json
```

这些数据只在本机使用。应用不会上传会话日志，除了调用本机 Codex 运行时读取实时额度外，不会主动发送网络请求。实时限额读取依赖本机 Codex 运行时，`codex app-server` 本身可能会通过你现有的 Codex 登录状态访问 Codex 的正常用量接口。

## 构建

要求：

- macOS 13 或更新版本
- Xcode Command Line Tools
- 已安装 `swiftc`

构建应用：

```bash
./build.sh
```

构建结果：

```text
build/Codex Token Meter.app
```

安装到 `/Applications` 并启动：

```bash
./install.sh
```

打包 DMG：

```bash
./package_dmg.sh
```

DMG 输出路径：

```text
dist/Codex-Token-Meter-0.1.7.dmg
```

## 命令行检查

应用也支持从命令行打印统计结果，便于排查解析结果：

```bash
"./build/Codex Token Meter.app/Contents/MacOS/CodexTokenMeter" --print --hours=168
```

指定窗口和视图：

```bash
"./build/Codex Token Meter.app/Contents/MacOS/CodexTokenMeter" --print --window=month --quota=all
```

JSON 输出会包含 `model_limit_id`、`model_limit_name`、API 等价成本字段和 `external_api_cost` 状态。

## 项目结构

```text
Sources/CodexTokenMeter/main.swift   主程序、解析器、状态栏 UI、详情窗口
Resources/                          应用图标和状态栏资源
Tools/                              图标生成脚本
Info.plist                          macOS App 元信息
build.sh                            构建 .app
install.sh                          安装到 /Applications
package_dmg.sh                      打包 DMG
```

## License

MIT
