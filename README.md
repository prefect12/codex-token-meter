# Codex Token Meter

Codex Token Meter 是一个原生 macOS 状态栏工具，用来查看本机 Codex 的 token 消耗、缓存命中率和实时剩余额度。

它直接读取本地 Codex 会话日志：

```text
~/.codex/sessions/**/rollout-*.jsonl
```

并在可用时通过本机 `codex app-server` 读取实时限额信息，例如 5 小时窗口、周窗口、重置时间和剩余比例。

## 功能

- 状态栏显示当前剩余额度或用量摘要。
- 弹窗支持 `24h / 7d / 30d` 切换。
- 支持 `All / Spark / Other` 视图，区分 Codex 总用量、`GPT-5.3-Codex-Spark` 和非 Spark 模型。
- 显示 input、output、cached input、fresh input、total token。
- 显示实时 5 小时额度、周额度、缓存命中率和下次刷新时间。
- 详情窗口展示过去一年 GitHub 绿点风格日历。
- 点击某一天可查看当天总量、输入/输出、缓存/新输入、模型级拆分。
- 模型页面展示过去一年按模型聚合的 token 开销。
- 设置页支持 English、中文、日本語。
- 支持复制摘要、打开本地日志目录、手动刷新。

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
dist/Codex-Token-Meter-0.1.0.dmg
```

## 命令行检查

应用也支持从命令行打印统计结果，便于排查解析结果：

```bash
"./build/Codex Token Meter.app/Contents/MacOS/CodexTokenMeter" --print --hours=168
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
