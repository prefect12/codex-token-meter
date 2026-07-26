# Architecture Notes

## Current Assessment

The app is a small native macOS menu bar utility built directly with `swiftc`. Source is split by responsibility under `Sources/CodexTokenMeter`, while `main.swift` remains the only file with top-level command-line and `NSApplication` startup code.

The split is intentionally conservative: code moved by section, with behavior preserved. Future work should use the file map below and avoid changing accounting semantics while working on UI or copy.

## Source Map

- `Sources/CodexTokenMeter/DomainModels.swift`: token usage structs, report rows, account usage snapshots, API cost estimate structs.
- `Sources/CodexTokenMeter/LocalizationSettings.swift`: app language, localized text, currencies, user defaults, launch-at-login, external API cost file, quota warning settings.
- `Sources/CodexTokenMeter/LiveQuotaStatus.swift`: quota view selection, rate window pacing, OpenAI/Codex status-page reader.
- `Sources/CodexTokenMeter/CostEstimation.swift`: weekly reset observations, `QuotaCycleStore` per-reset-cycle usage history (5h and weekly windows, keyed by `resetsAt` with drift tolerance; legacy seeds are rebuilt in file version 2 from observed usage-drop events so ranges are contiguous and mid-cycle promo refreshes survive), historical quota-value estimates, API-equivalent allocation helpers.
- `Sources/CodexTokenMeter/ScannerReaders.swift`: rollout JSONL scanner/cache plus direct, read-only ChatGPT backend readers for live quota, Profile API usage, and reset credits.
- `Sources/CodexTokenMeter/ClaudeTokenScanner.swift`: Claude Code local JSONL scanner, usage aggregation, and repo-insight adapter.
- `Sources/CodexPetBar/ClaudeHomeActivityReader.swift`: Task Bar's read-only Claude Desktop Home conversation-list reader. It decompresses Chromium's externalized IndexedDB values locally and extracts only conversation metadata needed for recent-task rows.
- `Sources/CodexTokenMeter/StorageScanner.swift`: read-only local disk usage scanner for `~/.codex` and `~/.claude`; categorizes files, assigns cleanup risk, buckets 90-day growth by file modification day, and attributes session-log bytes to projects by reading only the head of each session JSONL for its `cwd`. It never deletes anything. `StorageSnapshotCacheStore` persists the last snapshot so the storage page can show cached results instantly while a background rescan runs.
- `Sources/CodexTokenMeter/DashboardViews.swift`: status item popover, rings, bullet quota display, charts, service-status chip.
- `Sources/CodexTokenMeter/DetailsWindow.swift`: details-window controller plus `UsageDetailsView` state, navigation, lifecycle, shared control setup, preferred-height calculation, and event dispatch. Page drawing belongs in the focused files below.
- `Sources/CodexTokenMeter/OverviewDetailsDrawing.swift`: overview metric cards, reset-credit countdown, source/model summaries, and related tooltip drawing.
- `Sources/CodexTokenMeter/InsightsDetailsDrawing.swift` and `InsightsDetailsCopy.swift`: repository-insight list/detail/heatmap/time views and their localized product copy.
- `Sources/CodexTokenMeter/CalendarQuotaDetailsDrawing.swift`: calendar selection details, Profile API fallback presentation, quota-cycle history, and legacy cost helpers still shared by those pages.
- `Sources/CodexTokenMeter/SettingsCostDetailsDrawing.swift`: settings-page sections and retained cost-history/ring drawing helpers.
- `Sources/CodexTokenMeter/ContributionDetailsDrawing.swift`: about page plus the contribution calendar grid, range summaries, and calendar hover details shared by overview/calendar.
- `Sources/CodexTokenMeter/StorageDetailsDrawing.swift` and `StorageDetailsCopy.swift`: read-only storage-page layout, controls, charts, project rows, tooltips, export UI, and localized copy.
- `Sources/CodexTokenMeter/DetailsDrawingPrimitives.swift`: shared AppKit panels, buttons, text alignment, donut paths, and contribution intensity colors.
- `Sources/CodexTokenMeter/ModelDetailsSupport.swift`: model-page filtering, sorting, unknown-label suppression, table-height calculation, and model/pricing coverage metrics. Keep these data transformations separate from AppKit drawing.
- `Sources/CodexTokenMeter/ModelDetailsDrawing.swift`: model-page source rows, full model table, share bar, data-trust panel, and hover tooltip drawing. It extends `UsageDetailsView` and uses only the module-internal drawing primitives and state explicitly exposed by `DetailsWindow.swift`.
- `Sources/CodexTokenMeter/DiagnosticsDetailsDrawing.swift`: diagnostics-page source health, API file, tool detection, and local log probe rendering. Keeping these read-only probes out of the window orchestrator makes their filesystem work and UI presentation easier to review together.
- `Sources/CodexTokenMeter/AppDelegate.swift`: timers, background scan queues, live refresh orchestration, settings callbacks.
- `Sources/CodexTokenMeter/FormattingCostHelpers.swift`: number formatting, date helpers, weekly/monthly cost rows.
- `Sources/CodexTokenMeter/CLIHelpers.swift`: CLI argument parsing and dashboard snapshot rendering.
- `Sources/CodexTokenMeter/main.swift`: `--print`, `--print-live`, `--print-profile`, `--print-service-status`, `--render-dashboard`, and app startup.
- `Resources/`: app icon, header logo, status bar template icon.
- `Tools/`: local Swift scripts that generate icon/logo assets.
- `build.sh`: creates the `.app` bundle and compiles all Swift sources under `Sources/CodexTokenMeter`.
- `install.sh`: builds, replaces `/Applications/AI Token Meter.app`, removes the old `/Applications/Codex Token Meter.app` bundle, and launches the renamed app.
- `package_dmg.sh`: builds, ad-hoc signs, and creates a DMG.

## Runtime Data Flow

1. `CodexTokenScanner` scans rollout logs from `AppSettings.logFolderURLs`.
2. It parses `token_count` events, converts cumulative counters into per-event deltas, and aggregates usage by hour, day, session, and model.
3. `ClaudeTokenScanner` scans Claude Code JSONL logs from `AppSettings.claudeLogFolderURLs`, reads assistant `usage` records, dedupes partial/final assistant snapshots by message ID, and aggregates usage by hour, day, session, model, and repository.
4. Day/week/month Codex windows can reuse day-level parsed-rollout caches; rolling `24h` windows stay event-based. Claude scans stay file/event based.
5. Task Bar separately reads Claude Desktop's local Home conversation-list cache from the claude.ai IndexedDB blob directory. Home rows use cached `updated_at` as recent/unread activity and never infer a running state because the persisted list does not expose generation status.
6. `LiveRateLimitReader` reads `https://chatgpt.com/backend-api/wham/usage` directly with the existing local ChatGPT credentials. The response is cached in memory, successful snapshots are persisted, and failures use 1/5/15-minute backoff without launching Codex processes.
7. `ClaudeOAuthUsageRefresher` refreshes Claude quota through the read-only OAuth usage endpoint during the normal live-refresh cycle. App launch checks only legacy ACL metadata and silently reuses an existing persistent `/usr/bin/security` grant; it never requests Keychain access automatically. A new or revoked grant can be requested only through the explicit `--grant-claude-keychain` command, where choosing **Always Allow** persists Apple's stable system tool in the legacy decrypt ACL instead of authorizing each newly built AI Token Meter CDHash. Before every background read, the app checks the ACL and login-keychain lock state without decrypting the item; missing persistent authorization or a locked keychain silently falls back to statusline/cache data instead of launching a password dialog. Rotated OAuth credentials are written back to their original shared source so Claude Code and AI Token Meter stay on the same refresh-token version. File-based credentials at `~/.claude/.credentials.json` are atomically written with mode `0600`. `ClaudeStatuslineStore` also captures optional Claude Code statusline `rate_limits` via `--claude-statusline` and exposes them as a local `LiveRateLimit` with `id=claude`.
8. `AccountUsageReader` reads `https://chatgpt.com/backend-api/wham/profiles/me` when Profile API totals are enabled and falls back to its last persisted snapshot when unavailable. Reset-credit details use the corresponding read-only `wham` endpoint and cache.
9. `CodexServiceStatusReader` reads `https://status.openai.com/api/v2/summary.json` for Codex component status.
10. `AppDelegate` merges Codex scans, Claude scans, optional Profile API totals, live quota limits, service status, and cost reference reports into `DashboardState`. The menu dashboard can seed this state from the last aggregate dashboard cache and last successful live quota cache while fresh scans run.
11. `DashboardView` renders the menu popover; `UsageDetailsView` renders details pages directly with AppKit drawing.

## Accounting Invariants

- Rollout `token_count` counters are cumulative within a rollout. Usage must be calculated as a non-negative delta from the previous counter.
- Claude Code assistant usage records are per-message counts. Do not delta them like Codex cumulative `token_count` rows.
- Claude Code can write partial and final assistant snapshots with the same message ID. Keep the final/largest token snapshot instead of summing duplicates.
- `Usage.total` should be treated as the source total for display and API-equivalent coverage.
- `freshInput = input - cachedInput`, clamped at zero.
- For Claude Code, `cache_read_input_tokens` maps to cached input. `cache_creation_input_tokens` and nested `cache_creation.ephemeral_5m_input_tokens` / `ephemeral_1h_input_tokens` count as input, but API-equivalent cost prices them with cache-write rates.
- Cache percentage is `cachedInput / input * 100`.
- Live quota rings and menu titles show remaining quota, not used quota.
- The learned model-limit ID comes from live rate limits when available, with `AppSettings.fallbackModelLimitID` only as a fallback.
- Profile API totals can provide larger lifetime/day totals, but zero Profile API days should fall back to local rollout data when local usage exists.
- Subscription-value estimates are local heuristics, not official billing.
- Codex and Claude subscription settings are platform-scoped. Each platform keeps its own monthly plan cost, payment currency, display currency, and payment start date; the combined cost view converts those platform plans before summing.
- API-equivalent cost is separate from subscription value and prices recognized model names by fresh input, cached input, and output.
- Do not add `reasoning_output_tokens` again to API-equivalent cost unless Codex changes the meaning of `total_tokens`.

## Storage And Cache Files

The app reads user data locally:

```text
~/.codex/sessions
~/.codex/archived_sessions
$CODEX_HOME/sessions
$CODEX_HOME/archived_sessions
~/.claude/projects
~/Library/Application Support/Claude/IndexedDB/https_claude.ai_0.indexeddb.blob
~/Library/Application Support/Codex Token Meter/ParsedRollouts
~/Library/Application Support/Codex Token Meter/claude-statusline.json
~/Library/Application Support/Codex Token Meter/api-usage.json
~/Library/Application Support/Codex Token Meter/cost-history.json
~/Library/Application Support/Codex Token Meter/machine-usage-history.json
~/Library/Application Support/Codex Token Meter/dashboard-report-cache.json
~/Library/Application Support/Codex Token Meter/details-snapshot-cache.json
~/Library/Application Support/Codex Token Meter/live-limits-cache.json
~/Library/Application Support/Codex Token Meter/storage-snapshot-cache.json
```

`storage-snapshot-cache.json` stores the last local disk-usage snapshot, including category roots and per-project paths. Those local paths are the essential content of a disk-usage report, so this cache intentionally keeps them; it must never contain log file contents.

`machine-usage-history.json` stores only aggregate local Codex usage by day, a stable per-installation ID and sampled official quota percentages. It must never contain rollout contents, session paths, prompts, account credentials, or raw Profile API responses. Its export is one ZIP archive containing a JSON report, CSV tables, and an accounting note so multiple machines can be compared without summing account-level quota percentages.

The application support directory intentionally keeps the old `Codex Token Meter` folder name so existing settings, caches, and optional cost files survive the `AI Token Meter` rename. `ParsedRollouts` is a derived cache. `dashboard-report-cache.json` stores aggregate `24h / 7d / 30d` dashboard reports for `All / Codex / Claude`; it must not store raw log content or local session paths. `details-snapshot-cache.json` stores the aggregate details-window snapshot used by overview, calendar, cost, model, and repository-insight pages; it must strip top-session paths and real repository paths before writing. `live-limits-cache.json` stores the last successfully parsed official quota windows so transient network or auth failures do not replace a known quota with a synthetic value. If the parsed-rollout cache schema changes, bump `DiskFileCache.version` and decide whether to support migration from the previous format.

## Development Checks

Run this after every source change:

```bash
./build.sh
```

For parser, cache, model, or cost changes:

```bash
"./build/AI Token Meter.app/Contents/MacOS/CodexTokenMeter" --print --window=week --quota=all
"./build/AI Token Meter.app/Contents/MacOS/CodexTokenMeter" --print --window=week --quota=claude
"./build/AI Token Meter.app/Contents/MacOS/CodexTokenMeter" --print --window=month --quota=codex
```

For Claude Code official rate limits, configure Claude Code statusline to run:

```bash
"/Applications/AI Token Meter.app/Contents/MacOS/CodexTokenMeter" --claude-statusline
```

The command reads Claude Code's statusline JSON from stdin and atomically writes `claude-statusline.json` under Application Support.

For live quota changes:

```bash
"./build/AI Token Meter.app/Contents/MacOS/CodexTokenMeter" --print-live
```

For Profile API changes:

```bash
"./build/AI Token Meter.app/Contents/MacOS/CodexTokenMeter" --print-profile
```

For service-status changes:

```bash
"./build/AI Token Meter.app/Contents/MacOS/CodexTokenMeter" --print-service-status
```

For popover UI changes:

```bash
"./build/AI Token Meter.app/Contents/MacOS/CodexTokenMeter" --render-dashboard=/tmp/ai-token-meter-dashboard.png
```

For storage page changes:

```bash
"./build/AI Token Meter.app/Contents/MacOS/CodexTokenMeter" --render-details=/tmp/ai-token-meter-storage.png --section=storage
"./build/AI Token Meter.app/Contents/MacOS/CodexTokenMeter" --render-details=/tmp/ai-token-meter-storage-claude.png --section=storage --details-source=claude
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
