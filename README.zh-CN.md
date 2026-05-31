# Codex Token Meter

[English README](README.md)

Codex Token Meter 是一个原生 macOS 状态栏工具，用来查看本机 Codex 的 token 消耗、缓存命中率、实时剩余额度、模型级用量和订阅金额估算。

它直接读取本地 Codex 会话日志：

```text
~/.codex/sessions/**/rollout-*.jsonl
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
- 支持 `All / Spark / Other` 视图，区分 Codex 总用量、`GPT-5.3-Codex-Spark` 和非 Spark 模型。
- 显示 5 小时额度、周额度、缓存命中率三个实时圆环。
- 展示 input、output、cached input、fresh input 和 total token。
- 详情窗口包含概览、模型、日历、金额、设置和关于页面。
- 过去 365 天日历热力图，点击某一天可查看当天用量详情。
- 模型页面按模型聚合长期 token 用量。
- 金额页面支持月付金额、本周剩余预算、历史消耗、当日价值和币种折算。
- 支持 English、简体中文、繁体中文、日本語、Français、Deutsch、Español、한국어。
- 数字单位会跟随界面语言：英文使用 `K / M / B`，中文使用 `万 / 亿`。
- 可配置 Codex 日志目录、状态栏显示内容、付款币种、展示币种和付费开始日期。
- 支持手动刷新、打开本地日志目录和命令行统计检查。

## 最近更新

- 将历史金额和额度价值估算收敛到统一的 `CostEstimator` 逻辑。
- 修复高 token 日期只显示几毛钱的问题，现在当日价值会按统一估算口径计算。
- 日历详情、模型行、金额总览、悬浮提示和历史金额页面都复用同一套金额估算。
- 修复英文界面数字单位：即使历史保存过中文单位偏好，英文界面也不会再显示 `万 / 亿`。
- 修复中文关于页残留英文说明，并压缩年度热力图下方过大的空白距离。

## 隐私说明

这个项目只包含应用源码和静态资源，不包含你的 Codex 日志、token 消耗数据、截图、构建产物或 DMG。

应用运行时会读取：

```text
~/.codex/sessions
~/Library/Application Support/Codex Token Meter/ParsedRollouts
```

这些数据只在本机使用。应用不会上传会话日志，也不会主动发送网络请求。实时限额读取依赖本机 Codex 运行时，`codex app-server` 本身可能会通过你现有的 Codex 登录状态访问 Codex 的正常用量接口。

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
dist/Codex-Token-Meter-0.1.3.dmg
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
