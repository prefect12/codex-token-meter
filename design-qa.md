# Model Routing Platform Button Style QA

## Evidence

- Problem reference: `/var/folders/hm/pmxxw3v90wl7nql88zsgljym0000gn/T/codex-clipboard-d0e1d426-8dad-44a5-b314-1af07f62a25b.png`
- Existing product pattern: `/var/folders/hm/pmxxw3v90wl7nql88zsgljym0000gn/T/codex-clipboard-01f8dcd3-54e6-44c3-b2c4-546ab4833112.png`
- Claude implementation: `/tmp/model-routing-button-style-claude.png`
- Codex implementation: `/tmp/model-routing-button-style-codex.png`
- Focused comparison: `/tmp/model-routing-button-style-comparison.png`
- Viewport: 1552 x 984 points at 2x density

## Findings

No actionable P0, P1, or P2 differences remain.

- Replaced the joined native segmented control with two independent rounded buttons.
- Selected and unselected fills, borders, corner radius, 8-point gap, typography, and 30-point height now reuse the same visual tokens as the existing source selector.
- The control remains right-aligned in the page header and keeps the existing Codex / Claude switching behavior.
- Both buttons expose radio-button accessibility roles, labels, and selected values.
- The Codex and Claude page renders show no overlap, clipping, or layout regression.

## Final result

Passed.

---

# Design QA: Codex / Claude model routing

## Source and implementation

- Source reference: `/var/folders/hm/pmxxw3v90wl7nql88zsgljym0000gn/T/codex-clipboard-8f0f700a-8ce3-485d-9577-6689b7d354db.png`
- Claude implementation: `/tmp/ai-token-meter-model-routing-claude-final.png`
- Codex regression view: `/tmp/ai-token-meter-model-routing-codex-final.png`
- Combined comparison: `/tmp/model-routing-reference-vs-implementation-final.png`
- Viewport: 1552 x 984 points, rendered at 2x density
- State: Default Model page, Claude selected, global settings visible, all projects shown

## Comparison

- The existing navigation, title, global card, search field, filter control, table, spacing, colors, typography, and row controls are preserved.
- A compact Codex / Claude segmented control was added in the page header, using the page's existing segmented-control treatment.
- Claude rows use the same columns and inheritance affordance as Codex rows.
- Shared Claude project settings remain visible but cannot falsely claim to follow the global setting.
- A persisted `max` value is labelled `max（仅会话）` and disabled because Claude Code does not accept it in persistent settings.
- The footer explains that project changes are written to the machine-private Claude settings file.

## Interaction checks

- Switching platforms reloads the corresponding global and project settings.
- Global model and effort controls write only their platform's settings keys.
- Claude project overrides write only `.claude/settings.local.json`.
- Shared `.claude/settings.json` content remains unchanged.
- Search, filters, inheritance controls, refresh, and Codex configuration continue to work through the existing control paths.

## Iteration history

1. Added the top platform selector and reused the existing routing table.
2. Added shared/local Claude precedence and disabled false global inheritance for shared overrides.
3. Updated the Claude model aliases and marked session-only effort values after checking current Claude Code documentation.
4. Rendered both platforms at the source viewport and compared the reference and implementation together.

## Final result

Passed. No P0, P1, or P2 visual or interaction issues remain in the verified state.

---

# Follow Global Control Design QA

## Evidence

- Source visual truth: `/var/folders/hm/pmxxw3v90wl7nql88zsgljym0000gn/T/codex-clipboard-3f1c7242-d3ee-404c-837e-768015ce57f7.png`
- Wide implementation: `/tmp/model-routing-follow-global-final.png`
- Compact implementation: `/tmp/model-routing-follow-global-final-compact.png`
- Combined comparison: `/tmp/model-routing-follow-global-comparison.png`
- Live-data implementation: `/tmp/model-routing-follow-global-v1.png`

## Normalization

- Source pixels: 1760 x 1374.
- Wide implementation pixels: 2560 x 1520 for a 1280 x 760 point AppKit view at 2x density.
- Compact implementation pixels: 1720 x 1520 for an 860 x 760 point AppKit view at 2x density.
- The source is a written interaction specification with the previous inherited controls, not a pixel-exact mock. The combined comparison scales both full views to 1600 pixels wide and judges the requested state changes rather than unrelated chat chrome.
- States shown together: multiple-root conflict, project settings, and following global.

## Findings

No actionable P0, P1, or P2 differences remain.

- Fonts and typography: the implementation retains the app's native San Francisco hierarchy. Inherited values no longer repeat `· 继承`; the single `跟随全局` column expresses the state.
- Spacing and layout rhythm: the checkbox is centered in the former status column at both 1280- and 860-point widths. Model and effort controls retain their existing column dimensions and row alignment.
- Colors and visual tokens: enabled controls keep the existing input treatment. Following-global controls use 52% opacity and are disabled. Mixed state uses the existing amber warning color and the native indeterminate checkbox.
- Image quality and asset fidelity: the design contains no raster assets. Native AppKit checkboxes and existing controls are used; no replacement drawings or placeholder icons were introduced.
- Copy and content: inherited controls show the actual effective global model and effort without duplicate inheritance labels. The table header is `跟随全局`.
- Interaction states: checking removes both project overrides; unchecking writes the current effective global model and effort as explicit project values before enabling editing. Multiple roots render as an amber indeterminate checkbox; AppKit advances the mixed checkbox to checked on activation.
- Accessibility: the checkbox is a native keyboard-focusable control with a project-specific accessibility label. Disabled pop-ups are removed from editing while still showing their effective values.

## Comparison History

### Iteration 1

- The selected direction required one row-level inheritance control, disabled inherited pop-ups, effective values without `· 继承`, and an indeterminate multiple-root state.
- The first implementation render contains all three states without layout collisions or repeated inheritance copy.
- Wide and compact post-implementation evidence: `/tmp/model-routing-follow-global-final.png` and `/tmp/model-routing-follow-global-final-compact.png`.

## Primary Interactions Tested

- Store test verifies different root values produce a mixed state.
- Store test verifies checking follow-global clears model and reasoning overrides from every root.
- Store test verifies unchecking creates project settings using the global Terra/medium values.
- AppKit probe verifies a mixed native checkbox advances to checked when activated.
- Build and both render widths completed without UI runtime errors.

## Follow-up Polish

- P3: run a manual VoiceOver announcement pass in the installed application.

final result: passed

# Hourly Legend Spacing QA

## Source and implementation

- Source visual truth: `/var/folders/hm/pmxxw3v90wl7nql88zsgljym0000gn/T/codex-clipboard-c435b54d-fbfc-4377-a2bf-5e4abd94a02f.png`, showing the reported cramped spacing.
- Before render: `/tmp/ai-token-meter-hourly-spacing-before.png`.
- Implementation screenshot: `/tmp/ai-token-meter-hourly-spacing-after.png`.
- Focused normalized comparison: `/tmp/ai-token-meter-hourly-spacing-comparison.png`.
- Full render viewport: 1280 x 760 points at 2x density; 2560 x 1520 pixels.
- Focused comparison: two equal 2138 x 190 pixel crops stacked into one 2138 x 380 pixel artifact.
- State: Chinese dark appearance, Hours page, current 24-hour range.

## Full-view and focused comparison evidence

- The legend moved down 12 points while the title and date/filter/range controls stayed fixed.
- The visible gap between the control row and model legend is now deliberate rather than nearly touching.
- The plot moved down by the same amount and became 12 points shorter, preserving its bottom edge, axis labels, hint, card height, and summary placement.
- No horizontal alignment, control sizing, or interaction target changed.

## Required fidelity surfaces

- Fonts and typography: unchanged system family, weights, sizes, and truncation behavior.
- Spacing and layout rhythm: the reported vertical crowding is resolved; the top rows now read as distinct control and legend groups.
- Colors and visual tokens: unchanged dark panel, semantic model colors, and selected control colors.
- Image quality and asset fidelity: no raster or generated assets are used in this native AppKit surface; SF Symbols and native drawing remain unchanged.
- Copy and content: all labels and model names remain unchanged.

## Findings and comparison history

- Before: P2 spacing issue between the toolbar controls and legend.
- Fix: moved the legend and plot origin down 12 points while keeping the plot bottom fixed.
- After: no actionable P0, P1, or P2 differences remain for the requested spacing change.

final result: passed

---

# Hourly Date Popover QA

## Source and implementation

- Source visual truth: `/Users/kadewu/.codex/generated_images/01a08254-218d-7822-a75d-73a7e083987f/exec-d4555a6d-105a-4f14-bbf6-9c904fd4c9cf.png`
- Deterministic component render: `/tmp/ai-token-meter-hourly-calendar-v2.png`
- Installed application surface: `/tmp/ai-token-meter-hourly-calendar-installed-window.png`
- Focused normalized comparison: `/tmp/ai-token-meter-hourly-calendar-comparison-v2.png`
- Full-view comparison: `/tmp/ai-token-meter-hourly-calendar-full-comparison.png`
- Source pixels: 1363 x 1154.
- Component pixels: 608 x 540 for a 304 x 270 point AppKit view at 2x density.
- Installed capture pixels: 3248 x 2008, including the 1512 x 892 point details window, popover, shadow, and capture padding at 2x density.
- State: Chinese dark appearance, September 2026, September 3 selected, September 9 current/maximum date, later dates disabled.

## Full-view comparison evidence

- The installed popover remains anchored to the hourly date button and stays inside the chart card.
- The surrounding hourly toolbar, source filters, 24h/48h selector, chart, summary, and model table retain their existing hierarchy and behavior.
- The source mock is a cropped concept view while the installed evidence shows the full details window, so pixel judgments for the surrounding chart are intentionally limited to structure and unchanged placement.

## Focused comparison evidence

- The focused comparison places the source calendar and deterministic AppKit render in the same 608 x 540 pixel frame.
- Typography uses the system family with matching semibold month hierarchy and compact numeric labels.
- Spacing matches the selected direction: 16-point side insets, full-width seven-column grid, one divider, compact 31-point row rhythm, and no unused right-side region.
- Colors follow the existing app tokens: dark navy surface, white primary text, restrained secondary text, system blue selection, cyan current-day outline, and dim disabled dates.
- Icons use SF Symbols for month navigation; there are no raster placeholders or invented decorative assets.
- Copy is localized as `2026年9月` and `日 一 二 三 四 五 六`.

## Findings

No actionable P0, P1, or P2 differences remain.

- The mock keeps the next-month arrow visually enabled, but the implementation disables it because September 9 is the maximum selectable date. This is an intentional product constraint, not design drift.
- The standalone component render omits the popover shell shadow and pointer; the installed AppKit surface supplies both.
- P3: the mock's month title is fractionally heavier. The installed system semibold weight is retained for consistency with the rest of AI Token Meter.

## Interaction and accessibility checks

- Opening the date button exposes one popover, a localized month title, two month-navigation buttons, and 42 date buttons in the accessibility tree.
- Every date button exposes a full localized date label; unavailable future dates are disabled.
- Selecting September 8 closes the popover, changes the date button to `09/08`, and loads the corresponding historical 48-hour report.
- Switching to August updates the title to `2026年8月` and enables forward-month navigation.
- Selecting August 31 closes the popover and changes the date button to `08/31`.
- Activating `今天` restores the default `现在` state and disables next-day/today actions again.
- A manual VoiceOver announcement pass was not performed.

## Comparison history

### Iteration 1

- P2: current-day treatment rendered as a rounded square instead of the source's circular outline.
- P2: disabled future dates were too faint to scan.

### Iteration 2

- Changed the current-day outline to a 28-point circle.
- Raised disabled-date contrast while preserving the unavailable state.
- Rebuilt, rerendered, and repeated the same normalized comparison; both P2 findings are resolved.

final result: passed
