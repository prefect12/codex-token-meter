# Codex Token Meter

[中文说明](README.zh-CN.md)

Codex Token Meter is a native macOS menu bar app for tracking local Codex token usage, cache hit rate, live quota remaining, model-level usage, and estimated subscription value.

It reads your local Codex session logs directly:

```text
~/.codex/sessions/**/rollout-*.jsonl
~/.codex/archived_sessions/rollout-*.jsonl
$CODEX_HOME/sessions/**/rollout-*.jsonl
$CODEX_HOME/archived_sessions/rollout-*.jsonl
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
- Cost page for monthly plan cost, remaining budget, historical spend, estimated daily value, and API-equivalent token cost.
- Default scan coverage for current sessions, archived sessions, and `CODEX_HOME` when that environment variable is set.
- Localized UI for English, Simplified Chinese, Traditional Chinese, Japanese, French, German, Spanish, and Korean.
- Language-aware number units: English uses `K / M / B`; Chinese uses `万 / 亿`.
- Configurable Codex log folder, menu bar display mode, launch at login, payment currency, display currency, and payment start date.
- Manual refresh, local log folder shortcut, and CLI inspection mode.

## Data And Calculation Model

Codex Token Meter uses two local data sources:

- **Token usage** comes from local Codex session logs. By default the app scans `~/.codex/sessions`, `~/.codex/archived_sessions`, and matching `sessions` / `archived_sessions` folders under `$CODEX_HOME` when that environment variable is set. If you choose a custom log folder in Settings, that folder overrides the default roots. The app scans `token_count` events, reads `input_tokens`, `cached_input_tokens`, `output_tokens`, `reasoning_output_tokens`, and `total_tokens`, calculates the delta between adjacent cumulative counters, and aggregates those deltas by hour, day, session, and model.
- **Live quota percentages** come from the local Codex runtime. The app starts `codex app-server`, calls `account/rateLimits/read`, and reads fields such as `usedPercent` and `resetsAt` for the 5-hour and weekly windows. Remaining quota in the menu bar and quota rings is displayed as `100 - usedPercent`.
- **Cache percentage** comes from local token detail and is calculated as `cached_input_tokens / input_tokens * 100`.
- **Cost estimates** are not official billing. The monthly plan cost comes from settings and defaults to `$200`; weekly budget is `monthly plan cost * 12 / 52`. Current-week used value prefers the live weekly `usedPercent`. Historical days and weeks are estimated from local token usage, historical peaks, and recorded weekly quota percentages.
- **API-equivalent cost** is a separate estimate. It answers: "if this same local Codex token usage had been billed directly through API-style token pricing, roughly how much would it cost?" The app prices recognized models by token type: fresh input, cached input, and output. Current built-in rates use the official API prices for GPT-5.5, GPT-5.4, and GPT-5.4 mini, plus the token-based Codex rate-card equivalent for GPT-5.3-Codex / GPT-5.2-style Codex models. `reasoning_output_tokens` is not added again because local `total_tokens` already equals input plus output in Codex token-count events. Unknown model labels are left unpriced and reduce the displayed priced-token coverage.

If OpenAI resets or refreshes your quota during a week, the live weekly percentage follows the new `usedPercent`, so the menu bar and weekly quota ring may suddenly show more remaining quota. Local token logs are not cleared. The cost page records observed weekly-percentage drops and keeps the highest weekly percentage seen for historical weeks so past estimated value is not overwritten by a later low live percentage. This is still a local observation-based estimate, not an official billing export.

If you run work through Codex CLI or the Codex app with API-based authentication, local token usage can still be counted as long as Codex continues writing local `rollout-*.jsonl` logs. Live quota percentages depend on whether `codex app-server` can return `account/rateLimits/read` for that authentication mode. Direct OpenAI API calls that bypass the local Codex client are not tracked today; supporting them would require adding a separate data source for API response usage, organization usage, or billing data.

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
~/.codex/archived_sessions
$CODEX_HOME/sessions
$CODEX_HOME/archived_sessions
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
dist/Codex-Token-Meter-0.1.4.dmg
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
