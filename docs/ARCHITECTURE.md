# Architecture Notes

## Current Assessment

The app is a small native macOS menu bar utility built directly with `swiftc`. Source is split by responsibility under `Sources/CodexTokenMeter`, while `main.swift` remains the only file with top-level command-line and `NSApplication` startup code.

The split is intentionally conservative: code moved by section, with behavior preserved. Future work should use the file map below and avoid changing accounting semantics while working on UI or copy.

## Source Map

- `Sources/CodexTokenMeter/DomainModels.swift`: token usage structs, report rows, account usage snapshots, API cost estimate structs.
- `Sources/CodexTokenMeter/LocalizationSettings.swift`: app language, localized text, currencies, user defaults, launch-at-login, external API cost file, quota warning settings.
- `Sources/CodexTokenMeter/LiveQuotaStatus.swift`: quota view selection, rate window pacing, OpenAI/Codex status-page reader.
- `Sources/CodexTokenMeter/CostEstimation.swift`: weekly reset observations, historical quota-value estimates, API-equivalent allocation helpers.
- `Sources/CodexTokenMeter/ScannerReaders.swift`: rollout JSONL scanner/cache, `codex app-server` live quota reader, Profile API usage reader.
- `Sources/CodexTokenMeter/DashboardViews.swift`: status item popover, rings, bullet quota display, charts, service-status chip.
- `Sources/CodexTokenMeter/DetailsWindow.swift`: overview, model, calendar, cost, diagnostics, settings, and about pages.
- `Sources/CodexTokenMeter/AppDelegate.swift`: timers, background scan queues, live refresh orchestration, settings callbacks.
- `Sources/CodexTokenMeter/FormattingCostHelpers.swift`: number formatting, date helpers, weekly/monthly cost rows.
- `Sources/CodexTokenMeter/CLIHelpers.swift`: CLI argument parsing, dashboard snapshot rendering, and details-page snapshot rendering.
- `Sources/CodexTokenMeter/main.swift`: `--print`, `--print-live`, `--print-profile`, `--print-service-status`, `--render-dashboard`, `--render-details`, and app startup.
- `Resources/`: app icon, header logo, status bar template icon.
- `Tools/`: local Swift scripts that generate icon/logo assets.
- `build.sh`: creates the `.app` bundle and compiles all Swift sources under `Sources/CodexTokenMeter`.
- `install.sh`: builds, replaces `/Applications/Codex Token Meter.app`, and launches it.
- `package_dmg.sh`: builds, ad-hoc signs, and creates a DMG.

## Runtime Data Flow

1. `CodexTokenScanner` scans rollout logs from `AppSettings.logFolderURLs`.
2. It parses `token_count` events, converts cumulative counters into per-event deltas, and aggregates usage by hour, day, session, and model.
3. Day/week/month windows can reuse day-level parsed-rollout caches; rolling `24h` windows stay event-based.
4. `LiveRateLimitReader` starts `codex app-server` and reads `account/rateLimits/read`.
5. `AccountUsageReader` reads `account/usage/read` when Profile API totals are enabled.
6. `CodexServiceStatusReader` reads `https://status.openai.com/api/v2/summary.json` for Codex component status.
7. `AppDelegate` merges local scans, optional Profile API totals, live quota limits, service status, and cost reference reports into `DashboardState`.
8. `DashboardView` renders the menu popover; `UsageDetailsView` renders details pages directly with AppKit drawing.

## Accounting Invariants

- Rollout `token_count` counters are cumulative within a rollout. Usage must be calculated as a non-negative delta from the previous counter.
- `Usage.total` should be treated as the source total for display and API-equivalent coverage.
- `freshInput = input - cachedInput`, clamped at zero.
- Cache percentage is `cachedInput / input * 100`.
- Live quota rings and menu titles show remaining quota, not used quota.
- The learned model-limit ID comes from live rate limits when available, with `AppSettings.fallbackModelLimitID` only as a fallback.
- Profile API totals can provide larger lifetime/day totals, but zero Profile API days should fall back to local rollout data when local usage exists.
- Subscription-value estimates are local heuristics, not official billing.
- API-equivalent cost is separate from subscription value and prices recognized model names by fresh input, cached input, and output.
- Do not add `reasoning_output_tokens` again to API-equivalent cost unless Codex changes the meaning of `total_tokens`.

## Storage And Cache Files

The app reads user data locally:

```text
~/.codex/sessions
~/.codex/archived_sessions
$CODEX_HOME/sessions
$CODEX_HOME/archived_sessions
~/Library/Application Support/Codex Token Meter/ParsedRollouts
~/Library/Application Support/Codex Token Meter/api-usage.json
~/Library/Application Support/Codex Token Meter/cost-history.json
```

`ParsedRollouts` is a derived cache. If the cache schema changes, bump `DiskFileCache.version` and decide whether to support migration from the previous format.

## Development Checks

Run this after every source change:

```bash
./build.sh
```

For parser, cache, model, or cost changes:

```bash
"./build/Codex Token Meter.app/Contents/MacOS/CodexTokenMeter" --print --window=week --quota=all
"./build/Codex Token Meter.app/Contents/MacOS/CodexTokenMeter" --print --window=month --quota=other
```

For live quota changes:

```bash
"./build/Codex Token Meter.app/Contents/MacOS/CodexTokenMeter" --print-live
```

For Profile API changes:

```bash
"./build/Codex Token Meter.app/Contents/MacOS/CodexTokenMeter" --print-profile
```

For service-status changes:

```bash
"./build/Codex Token Meter.app/Contents/MacOS/CodexTokenMeter" --print-service-status
```

For popover UI changes:

```bash
"./build/Codex Token Meter.app/Contents/MacOS/CodexTokenMeter" --render-dashboard=/tmp/codex-token-meter-dashboard.png
```

For details-page UI changes:

```bash
"./build/Codex Token Meter.app/Contents/MacOS/CodexTokenMeter" --render-details=/tmp/codex-token-meter-details.png --details-section=overview --language=en
```

## Refactor Guidance

The first file split has already been done as a behavior-preserving change. Further refactors should be smaller than the initial split and should keep file boundaries aligned with the source map above.

Recommended rules:

1. Keep top-level command-line entrypoints and `NSApplication` startup in `main.swift`.
2. Keep `build.sh` source discovery intact so new Swift files are picked up automatically.
3. Prefer module-internal symbols for cross-file collaborators; avoid `public` unless this becomes a library.
4. Keep parser/cost/accounting changes covered by CLI `--print` checks.
5. Keep UI-only work in view files and verify with `--render-dashboard`.
6. Do not combine large structural refactors with feature work.
