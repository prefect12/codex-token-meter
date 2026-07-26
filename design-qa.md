# Design QA: Claude third ring selector

- Source visual truth: `/var/folders/hm/pmxxw3v90wl7nql88zsgljym0000gn/T/codex-clipboard-11b928c7-1f8f-40a5-acbe-45ce181e3b1d.png`
- Implementation screenshot: `/tmp/ai-token-meter-third-ring-fable.png`
- Alternate state: `/tmp/ai-token-meter-third-ring-cache.png`
- Settings screenshot: `/tmp/ai-token-meter-settings-third-ring.png`
- Viewport: 430 x 610 points, rendered at 2x
- State: Claude, 24h, rings, Fable 5 selected

## Full-view comparison evidence

The source and implementation were opened together at the same dashboard state. The implementation preserves the source layout while replacing the small Fable satellite with the same `RingView` frame used by the 5-hour and weekly quotas. All three ring frames, center values, titles, subtitles, and horizontal gaps align on one grid. The alternate cache state uses the same third frame without moving surrounding content.

The source includes surrounding popover/window chrome that the CLI render intentionally omits. This does not affect the dashboard content geometry.

## Focused-region evidence

No extra crop was needed because the three rings and all labels are legible in the full 2x render. The quota settings page was also rendered separately to verify the new segmented selector, hint text, and following switches fit without clipping or overlap.

## Required fidelity surfaces

- Fonts and typography: passed. Existing system and monospaced-digit fonts, weights, sizes, truncation, and hierarchy are reused by all three rings.
- Spacing and layout rhythm: passed. The dashboard uses the existing three-column calculation, giving all rings equal width and identical 136-point height. Settings rows remain separated and visible.
- Colors and visual tokens: passed. Fable 5 uses semantic system orange; cache hit retains the existing teal; all other opacity and background tokens are unchanged.
- Image quality and asset fidelity: passed. No new raster assets or substitute icons were required; the existing native logo and controls remain unchanged.
- Copy and content: passed. The setting clearly names the Claude third ring and offers `缓存命中` / `Fable 5`, with localized explanatory text.

## Findings

No actionable P0, P1, or P2 differences remain.

## Comparison history

- Pass 1: the implementation already met the requested equal-size three-ring geometry. Both selector states and the settings page rendered without overlap, so no P0/P1/P2 correction loop was required.

## Follow-up polish

No P3 follow-up is required for this scope.

final result: passed

---

# Task Bar Plan Hover Design QA

## Evidence

- Source visual truth: `/var/folders/hm/pmxxw3v90wl7nql88zsgljym0000gn/T/codex-clipboard-e3df5924-8091-4107-9d06-5254d7711395.png`
- Implementation screenshot: `/tmp/task-bar-plan-no-title-large-text.png`
- Combined comparison: `/tmp/task-bar-plan-comparison.png`
- Source pixels: 740 x 604
- Implementation pixels: 1556 x 892
- Implementation AppKit size: 778 x 446 points at 2x density
- Comparison normalization: both captures scaled to 604 px high and placed side by side without changing aspect ratio
- State: dark appearance, fourth plan step active, task row hovered, complete five-step plan visible

## Full-View Comparison

The implementation intentionally removes the reference's `任务计划` header per the latest user direction. The recovered vertical space is given to the checklist: step labels are larger while the complete five-step plan and `Step 4 / 5` footer remain visible. The Task Bar header, filters, row density, fixed progress-ring column, hover highlight, and panel attachment point remain unchanged.

## Focused Region Comparison

The panel was checked at original 2x output:

- The panel uses a 360 pt card width, 10 pt pointer inset, 16 pt top inset, dynamically measured checklist rows, and a 42 pt footer.
- Step text increased from 10.5 pt to 12.5 pt; the active step uses semibold weight and the footer increased to 11.5 pt.
- Long Chinese and mixed Chinese/English labels wrap naturally with no truncation.
- Completed, active, and pending markers match the source's gray check, blue ring, and muted empty-ring hierarchy.
- All markers share one fixed x-axis and retain continuous dashed connectors.

## Required Fidelity Surfaces

- Fonts and typography: passed. Native system fonts preserve the existing Task Bar family; the requested larger 12.5 pt checklist text is readable, wraps fully, and uses an appropriate semibold active state.
- Spacing and layout rhythm: passed. Removing the redundant title leaves a compact 16 pt top inset, marker and text columns remain aligned, and the larger text does not collide with the footer or card edge.
- Colors and visual tokens: existing Task Bar charcoal surfaces and semantic green, amber, and blue are reused. The plan panel uses the same dark surface with restrained white opacity and the existing blue progress accent.
- Image quality and asset fidelity: the logo remains the repository's native Task Bar asset; icons use AppKit/SF Symbols; rings and checklist states are native vector drawing at display density with no raster placeholders.
- Copy and content: passed. The five runtime plan steps and step fraction remain complete; only the explicitly removed redundant title is absent.

## Comparison History

1. Earlier implementation included a `任务计划` heading and 10.5 pt step labels.
2. Fix: removed the heading, reduced the top region to a 16 pt inset, increased checklist text to 12.5 pt and footer text to 11.5 pt, and made row heights follow wrapped text.
3. Post-fix evidence: `/tmp/task-bar-plan-comparison.png` shows the deliberate title removal, larger readable steps, complete plan content, and unchanged status hierarchy.

## Findings

No actionable P0, P1, or P2 visual mismatches remain.

## Follow-up Polish

- P3: Image-generated source text has slightly softer antialiasing than native AppKit rendering; native rendering is intentionally retained for production sharpness.
- P3: The source is a focused crop while the implementation includes the full Task Bar fixture; this framing difference does not affect the hover-card comparison.

## Verification

- Task Bar build: passed with `./build_petbar.sh`
- Task Bar plan-hover render: passed at 778 x 446 points / 1556 x 892 pixels
- Hover routing: task-row entry and movement use the existing details card by default; only the 15 pt progress ring with a 4 pt hit inset selects the plan card.
- `git diff --check`: passed

final result: passed

---

# AI Token Meter Overview Weekly Quota Design QA

- Source visual truth: `/Users/kadewu/.codex/generated_images/019f9bb4-12c0-7e92-ad26-dd3bb00c646a/exec-03139954-67b0-48f8-b679-b25e902edce6.png`
- Implementation screenshot: `/tmp/ai-token-meter-overview-weekly-compact.png`
- Combined comparison: `/tmp/ai-token-meter-weekly-comparison.png`
- Viewport: native AppKit details view at 920 x 996 CSS points, 2x backing scale
- Source pixels: 1419 x 1109; window title bar removed for content comparison, then normalized to 1840 x 1370
- Implementation pixels: 1840 x 1992; top 1840 x 1370 compared at 1:1 pixels
- State: Overview, All sources, Chinese, live Codex and Claude weekly quota available

## Full-view comparison evidence

The selected asymmetrical layout is preserved: a two-row weekly quota panel occupies the left side of the top metric region, the five existing metrics use a 3-over-2 grid on the right, and the reset-credit, source, and model panels retain their established order and styling below. Sidebar proportions, source selector placement, panel fills, borders, radii, and semantic Codex/Claude colors align with the selected design.

Dynamic values intentionally differed from the design mock in that initial pass. It displayed the current Codex weekly used percentage, Claude weekly remaining percentage, and each provider's actual reset timestamp rather than the mock's 68% and 42% examples. The later weekly-remaining QA entry records the follow-up semantic correction.

## Focused region comparison evidence

The top quota-and-metrics region was inspected at equal pixel density in the combined comparison. Titles, percentage/suffix hierarchy, divider, progress tracks, reset timestamps, and 3-over-2 metric-card alignment are readable without overlap or truncation. A second full render at 1280 points confirmed that the same hierarchy expands cleanly at a wider desktop size.

## Findings

- No actionable P0, P1, or P2 mismatch.
- P3: the generated mock slightly reduces some pre-existing header and sidebar typography. The implementation intentionally preserves the app's native typography instead of restyling unrelated surfaces.
- P3: the design mock contains static example quota values; the implementation correctly uses live or cached quota data and shows an unavailable state when a weekly window is missing.

## Required fidelity surfaces

- Fonts and typography: native SF system fonts, weights, monospaced percentage digits, and existing hierarchy preserved; no wrapping or truncation at 920 and 1280 points.
- Spacing and layout rhythm: selected 40/60 top-region composition, 12-point gaps, two equal quota rows, and downstream vertical reflow match the design intent.
- Colors and visual tokens: existing panel, border, blue, amber, cyan, orange, green, and teal tokens are reused.
- Image quality and asset fidelity: no raster assets are required by this native data UI; existing SF Symbols and AppKit drawing remain unchanged.
- Copy and content: Chinese labels match the selected design; reset timestamps and quota values are live data.
- Interaction and states: existing source tabs remain functional; the quota panel is read-only, as indicated by the design.
- Accessibility: text keeps the app's existing contrast and scalable native font rendering; meaning is conveyed by labels and numbers in addition to color.

## Comparison history

- Initial comparison: no P0/P1/P2 findings, so no design-QA fix iteration was required.

## Follow-up polish

- If product feedback prefers the mock's smaller surrounding typography, evaluate that as a separate whole-page typography change rather than coupling it to this quota feature.

final result: passed

---

# AI Token Meter Weekly Remaining Pace Marker Design QA

- Source visual truth: `/var/folders/hm/pmxxw3v90wl7nql88zsgljym0000gn/T/codex-clipboard-3c97bcc5-792a-4d57-89f1-736a7e205fc9.png`
- Implementation screenshot: `/tmp/ai-token-meter-overview-weekly-remaining.png`
- Combined comparison: `/tmp/ai-token-meter-weekly-remaining-comparison.png`
- Source pixels: 686 x 450
- Implementation pixels: 1840 x 1992 at 2x backing scale
- Comparison pixels: 1504 x 450; the implementation quota panel was cropped without changing its aspect ratio, scaled to the source height, and placed beside the source
- State: Overview, All sources, Chinese, live Codex and Claude weekly windows available

## Comparison evidence

The source and implementation were inspected together in one comparison image. Both providers now use the same remaining-quota semantics: the percentage, suffix, and filled rail represent actual weekly quota remaining. Each rail also includes a short expected-remaining marker derived from the elapsed portion of that provider's current weekly window.

The linear rail adapts the source's circular indicator to the already selected overview-card design. A yellow marker means actual remaining is below expected remaining at the current time; a lime marker means actual remaining is at or above the time-based expectation. The marker does not replace or distort the provider-colored actual-remaining fill.

## Required fidelity surfaces

- Fonts and typography: passed. Both rows use identical remaining labels, monospaced percentage digits, weight, size, and alignment.
- Spacing and layout rhythm: passed. The new marker stays on the existing rail, preserves the divider and reset-time rows, and does not change the selected overview geometry.
- Colors and visual tokens: passed. Codex blue and Claude amber continue to identify actual quota; yellow and lime reuse the existing quota pace-marker semantics elsewhere in the app.
- Copy and content: passed. Codex and Claude both say weekly remaining in Chinese, Traditional Chinese, Japanese, and English. Percentages come from `remainingPercent`.
- Dynamic behavior: passed. Marker position comes from elapsed window time, uses each provider's own reset timestamp and window duration, and is hidden when the pace comparison cannot be calculated.
- Accessibility: passed. Provider labels, percentage values, the explicit remaining suffix, and reset timestamp convey the state without relying on marker color alone.

## Findings

No actionable P0, P1, or P2 visual or semantic mismatches remain.

## Comparison history

1. Initial implementation mixed Codex used percentage with Claude remaining percentage and had no time-position marker.
2. Fix: both rows now render remaining percentage and add the expected-remaining marker on the same rail.
3. Post-fix comparison shows Codex at 90% remaining with a yellow marker and Claude at 96% remaining with a lime marker, matching the supplied reference semantics.

## Verification

- `git diff --check`: passed
- `./build.sh`: passed; only pre-existing Codable and deprecated Security warnings were emitted
- Overview details render: passed at 920 x 996 points / 1840 x 1992 pixels
- Live quota check: Codex weekly remaining 90%; Claude weekly remaining 96%

final result: passed
