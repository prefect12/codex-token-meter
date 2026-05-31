# Codex Token Meter

[中文说明](README.zh-CN.md)

Codex Token Meter is a native macOS menu bar app for tracking local Codex token usage, cache hit rate, live quota remaining, model-level usage, and estimated subscription value.

It reads your local Codex session logs directly:

```text
~/.codex/sessions/**/rollout-*.jsonl
```

When available, it also reads live quota data from the local Codex runtime, including the 5-hour window, weekly window, reset time, and remaining percentage.

## Screenshots

### Menu Bar Dashboard

![Codex Token Meter menu bar dashboard](docs/images/en-menu-popover.png)

### Details Window

![Codex Token Meter details overview](docs/images/en-details-overview.png)

### Cost And Budget Tracking

![Codex Token Meter cost and budget page](docs/images/en-details-costs.png)

<details>
<summary>Chinese UI preview</summary>

![Codex Token Meter Chinese menu bar dashboard](docs/images/zh-menu-popover.png)

![Codex Token Meter Chinese details overview](docs/images/zh-details-overview.png)

![Codex Token Meter Chinese cost and budget page](docs/images/zh-details-costs.png)

</details>

## Features

- Menu bar status item showing remaining quota, weekly quota, daily tokens, or weekly tokens.
- Compact popover with `24h / 7d / 30d` windows.
- `All / Spark / Other` quota views for total Codex usage, `GPT-5.3-Codex-Spark`, and non-Spark usage.
- Live rings for 5-hour quota, weekly quota, and cache hit rate.
- Token breakdown for input, output, cached input, fresh input, and total tokens.
- Details window with overview, model, calendar, cost, settings, and about pages.
- 365-day activity calendar with daily detail cards.
- Model-level aggregation for long-term usage analysis.
- Cost page for monthly plan cost, remaining budget, historical spend, and estimated daily value.
- Localized UI for English, Simplified Chinese, Traditional Chinese, Japanese, French, German, Spanish, and Korean.
- Language-aware number units: English uses `K / M / B`; Chinese uses `万 / 亿`.
- Configurable Codex log folder, menu bar display mode, payment currency, display currency, and payment start date.
- Manual refresh, local log folder shortcut, and CLI inspection mode.

## Recent Updates

- Centralized historical cost and quota-value estimation into one shared `CostEstimator` path.
- Fixed day-value estimates so high-token days no longer show cents-level spend.
- Reused the same cost estimator across calendar details, model rows, amount totals, tooltips, and cost history.
- Fixed English UI number units so saved Chinese unit preferences cannot leak `万 / 亿` into English screens.
- Tightened Chinese localization on the About page and reduced excess spacing in the yearly heatmap area.

## Privacy

This repository contains only app source code and static assets. It does not include your Codex logs, token usage data, screenshots, build artifacts, or DMG files.

At runtime, the app reads:

```text
~/.codex/sessions
~/Library/Application Support/Codex Token Meter/ParsedRollouts
```

Those files are used locally on your Mac. The app does not upload session logs and does not actively send network requests. Live quota reading depends on your local Codex runtime; `codex app-server` may use your existing Codex login state to access normal Codex usage endpoints.

## Build

Requirements:

- macOS 13 or later
- Xcode Command Line Tools
- `swiftc`

Build the app:

```bash
./build.sh
```

Build output:

```text
build/Codex Token Meter.app
```

Install to `/Applications` and launch:

```bash
./install.sh
```

Package a DMG:

```bash
./package_dmg.sh
```

DMG output:

```text
dist/Codex-Token-Meter-0.1.3.dmg
```

## CLI Inspection

The built app can print parsed statistics from the command line, which is useful when checking parser behavior:

```bash
"./build/Codex Token Meter.app/Contents/MacOS/CodexTokenMeter" --print --hours=168
```

Example with a specific window and quota view:

```bash
"./build/Codex Token Meter.app/Contents/MacOS/CodexTokenMeter" --print --window=month --quota=all
```

## Project Layout

```text
Sources/CodexTokenMeter/main.swift   App, parser, menu bar UI, and details window
Resources/                          App icons and menu bar assets
Tools/                              Icon generation scripts
Info.plist                          macOS app metadata
build.sh                            Builds the .app bundle
install.sh                          Installs to /Applications
package_dmg.sh                      Packages the DMG
```

## License

MIT
