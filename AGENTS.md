# AI Token Meter Development Guide

## Project Shape

- This is a native macOS menu bar app built directly with `swiftc`.
- The app entrypoint lives in `Sources/CodexTokenMeter/main.swift`; supporting code is split into focused files under the same directory.
- The companion Task Bar app lives in `Sources/CodexPetBar/main.swift` and is part of the same product family, not a separate design surface.
- `build.sh` compiles every Swift file under `Sources/CodexTokenMeter`, so future file splits do not need build-script changes.
- Prefer small, behavior-preserving changes unless you are explicitly doing a planned refactor.
- Read `docs/ARCHITECTURE.md` before changing parser, quota, cost, or UI behavior.

## Build And Verification

- Compile check: `./build.sh`
- CLI parser check: `"./build/AI Token Meter.app/Contents/MacOS/CodexTokenMeter" --print --window=week --quota=all`
- Live quota check: `"./build/AI Token Meter.app/Contents/MacOS/CodexTokenMeter" --print-live`
- Service-status check: `"./build/AI Token Meter.app/Contents/MacOS/CodexTokenMeter" --print-service-status`
- Dashboard render check for UI changes: `"./build/AI Token Meter.app/Contents/MacOS/CodexTokenMeter" --render-dashboard=/tmp/ai-token-meter-dashboard.png`

`--print-live`, `--print-profile`, `--print-service-status`, and dashboard rendering can depend on Codex login state or network availability. Do not treat their unavailability as a compile regression unless the failure is caused by local code.

## Git Workflow

- Prefer merging changes through pull requests. Do not merge directly into `main` unless the user explicitly asks for it.
- All source, behavior, or UI changes must use this sequence: a focused branch → PR → merged `main` → fetch `origin/main` → build and install from that exact merged revision. Do not install an unmerged working-tree build as the delivered app.
- Before calling a change complete, verify the PR merge, confirm local `HEAD` equals `origin/main`, then run the relevant checks and validate the installed `/Applications/AI Token Meter.app` surface.

## Data Safety

- The app reads local Codex logs from `~/.codex` and optional `CODEX_HOME` roots. Do not commit, paste, or store user rollout logs.
- Keep diagnostics read-only. Do not add background uploads of session logs or token details.
- Build outputs, screenshots, app bundles, and DMGs are ignored and should stay out of commits.

## Implementation Rules

- Preserve the token accounting model: `token_count` rows contain cumulative counters within a rollout; reported usage is the non-negative delta from the previous counter.
- Keep rolling `24h` scans event-accurate. Day/week/month scans may use day-level aggregate cache when the active filters allow it.
- Cache format changes must bump `DiskFileCache.version` and keep or intentionally remove migration code.
- Live quota UI shows remaining quota: `100 - usedPercent`.
- Subscription-value estimates and API-equivalent costs are separate concepts. Do not mix their labels or calculations.
- API-equivalent cost should not add `reasoning_output_tokens` a second time because Codex `total_tokens` already includes output.
- If Profile API daily totals are zero for a local day with Codex logs, preserve the local fallback behavior.

## UI Consistency

- Keep Task Bar and AI Token Meter visually aligned because they live in the same repository and should feel like one product system.
- Before adding new Task Bar controls, popovers, buttons, labels, hover cards, or status states, check whether an existing AI Token Meter pattern can be reused or adapted first.
- Prefer shared AppKit interaction patterns: compact segmented button rows, consistent icon sizes, text weights, spacing, corner radii, hover states, and dark popover colors.
- Do not invent a new visual style for Task Bar unless the existing Token Meter pattern clearly does not fit; document the reason in the change summary when deviating.
- For Codex/Claude labels, status chips, and token/usage hover data, keep naming, color intensity, number formatting, and alignment consistent with the Token Meter dashboard wherever practical.
- When UI changes affect Task Bar, verify the installed `/Applications/Task Bar.app`; when they affect AI Token Meter, verify the installed `/Applications/AI Token Meter.app` or the relevant render command.

## Refactor Guidance

- Keep files focused by responsibility:
  1. Pure domain models stay in `DomainModels.swift`.
  2. Settings, localization, and currency helpers stay in `LocalizationSettings.swift`.
  3. Scanner and runtime readers stay in `ScannerReaders.swift`.
  4. Cost history and cost estimation stay in `CostEstimation.swift`.
  5. AppKit views stay in `DashboardViews.swift` and `DetailsWindow.swift`.
  6. App orchestration stays in `AppDelegate.swift`; CLI startup stays in `main.swift`.
- Keep top-level command-line entrypoints and `NSApplication` startup in `main.swift` while moving supporting code into new files.
- When a symbol must be used across files, keep it module-internal by default and avoid widening to `public`.

## Asset Workflow

- Icons and menu assets live under `Resources/`.
- Icon generation scripts live under `Tools/`.
- Only regenerate assets when needed: `REGENERATE_ASSETS=1 ./build.sh`.
