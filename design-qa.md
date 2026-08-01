# Default Model Page Design QA

## Evidence

- Source visual truth: `/Users/kadewu/.codex/generated_images/019fbb0d-6957-7be0-93b4-8909ce1a6cff/call_qhEnGlFUew4eT2J1AVGSxCTG.png`
- Implementation screenshot: `/tmp/codex-token-meter-model-defaults-final-v2.png`
- Normalized implementation: `/tmp/codex-token-meter-model-defaults-final-v2-1x.png`
- Full-view comparison: `/tmp/codex-token-meter-model-defaults-comparison-v2.png`
- Focused content comparison: `/tmp/model-routing-focused-comparison.png`
- Search state: `/tmp/codex-token-meter-model-defaults-search-v2-1x.png`
- Inherited-only state: `/tmp/codex-token-meter-model-defaults-inherited-v2-1x.png`
- Compact-width state: `/tmp/codex-token-meter-model-defaults-compact-v2-1x.png`

## Normalization

- Target viewport and state: native macOS details window, dark appearance, default-model page, 1440 x 1024 points, global Terra/medium, four overridden projects, one inherited project.
- Source pixels: 1488 x 1058. It was normalized to 1440 x 1024 for full-view comparison.
- Implementation pixels: 2880 x 2048 from the AppKit 2x renderer. CSS/AppKit size: 1440 x 1024 points at density 2. It was downsampled to 1440 x 1024 before comparison.
- Compact implementation: 1720 x 1520 pixels, normalized to 860 x 760 points.

## Findings

No actionable P0, P1, or P2 differences remain.

- Fonts and typography: both use the native San Francisco system family and the same bold-title/semibold-control hierarchy. The implementation retains AI Token Meter's existing 26/13-point page header and compact table type, which is slightly denser than the concept but consistent with every other details page.
- Spacing and layout rhythm: global defaults, search/filter toolbar, unified table, inherited divider, and footer follow the source hierarchy. The implementation keeps the product's existing 200-point sidebar instead of widening it to the generated concept's approximate 290-point sidebar. At 860 points, project text truncates and controls remain usable without overlap.
- Colors and visual tokens: the implementation uses the app's existing background, panel, input, border, and accent-blue tokens. Selected navigation and filter states are blue; inherited and saved states remain deliberately quieter.
- Image quality and asset fidelity: the target contains no photographic or illustrative assets. All icons are native SF Symbols, matching the existing app; no replacement image, custom SVG, or placeholder asset is present.
- Copy and content: all core labels match the selected concept. In inherited rows, the implementation adds `· 继承` to the effective model/effort values so the control remains truthful. The footer action is `重新读取项目…` rather than `添加项目…` because Codex owns its project registry and this app should not create opaque registry records.
- Accessibility and behavior: native search, segmented filters, pop-up controls, accessibility labels, focus behavior, and keyboard semantics are retained. Search and inherited-only render states passed. The config-store test passed for global writes, multi-root project writes, inheritance removal, and preservation of unrelated TOML.

## Comparison History

### Iteration 1

- Earlier P2: inherited pop-up items reused the exact title of a model/effort item. `NSPopUpButton` de-duplicated that title and displayed the first catalog value (`Sol/low`) instead of the effective inherited value.
- Fix: make inherited display titles unique (`GPT-5.6-Terra · 继承`, `medium · 继承`) while preserving the inheritance sentinel as the represented value.
- Post-fix evidence: `/tmp/codex-token-meter-model-defaults-final-v2-1x.png` and `/tmp/codex-token-meter-model-defaults-inherited-v2-1x.png`.

### Iteration 2

- Earlier P2: the default AppKit segmented renderer showed a neutral-gray selected filter, and the search field had a doubled bezel in bitmap rendering.
- Fix: apply the app accent blue through `selectedSegmentBezelColor`; draw one shared input surface and make the native search field bezel/background transparent.
- Post-fix evidence: `/tmp/codex-token-meter-model-defaults-comparison-v2.png`.

## Primary Interactions Tested

- Search query state: `Arachne` filters the table to one row.
- Filter state: `继承全局` filters the table to the inherited project.
- Responsive state: 860 x 760 keeps all columns and controls usable.
- Persistence path: isolated temporary `CODEX_HOME` tests write and read global and project-local TOML without touching real user configuration.
- Build/render console: no UI runtime error was emitted. Existing unrelated Swift deprecation and immutable-decoding warnings remain.

## Follow-up Polish

- P3: a future live UI automation test could click each native pop-up control end-to-end; current coverage exercises its persistence path and rendered states separately.

final result: passed
