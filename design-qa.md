# Task Bar visual QA — Vibe Island direction

## Comparison target

- Source visual truth: `/var/folders/hm/pmxxw3v90wl7nql88zsgljym0000gn/T/codex-clipboard-9a231fbd-d2c5-4315-8ad2-e9b381de7a20.png`
- Implementation capture: `/tmp/taskbar-vibe-island-first.png`
- Combined comparison: `/tmp/taskbar-vibe-island-comparison.png`
- State: dark-mode Task Bar popover, `All` selected, three running tasks, one completed task, and expanded subtasks.
- Source dimensions: 2486 × 888 pixels. Implementation dimensions: 920 × 1240 pixels (`460 × 620` AppKit points at 2×). For full-view comparison the source was scaled to 920 × 329 pixels and stacked above the 920-pixel-wide implementation. This is a style comparison rather than a literal layout clone: the source is a wide desktop scene, while the implementation is a compact menu-bar popover.

## Findings

- No actionable P0/P1/P2 findings.
- Intentional deviation: the source places its translucent workflow panel over a colorful desktop scene. Task Bar stays opaque-near-black because its dense live task text needs dependable contrast over arbitrary macOS wallpaper. The matched surfaces are the rounded dark shell, fine light borders, layered translucent cards, warm orange emphasis, and high-contrast compact controls.

## Fidelity surfaces

- **Typography:** System type remains appropriate for a native AppKit utility. The title is raised to 18pt bold, with a 9.5pt monospaced live-status eyebrow and existing readable task hierarchy. Long task titles still truncate rather than collide with progress, pin, or subtask controls.
- **Spacing and layout rhythm:** The popover widens to 460pt; the 76pt status header, 48pt segmented filter, 12pt card gutters, 14pt card radii, and 98pt standard rows create the intended layered rhythm without hiding the footer.
- **Colors and tokens:** Near-black base (`0.035/0.037/0.050`), subtly warm panel gradient, translucent charcoal cards, one-pixel low-alpha borders, and orange primary accent produce the requested direction while preserving semantic green/yellow/blue task states.
- **Image and icon fidelity:** There are no user-provided application assets to reproduce. Existing native SF Symbols and the Task Bar mark are preserved; no placeholder imagery was introduced. The reference's desktop wallpaper is intentionally not copied into a functional task-monitor surface.
- **Copy and affordances:** `LIVE WORKSPACE`, status chips, filter labels, task cards, pins, progress rings, settings, and quit retain their clear existing meaning. Tabs and task actions keep their original code paths.

## Interaction and verification

- `./build_petbar.sh` passed.
- `TaskBar --self-test-plan-parser` passed.
- The real AppKit render command produced the implementation capture above.
- `git diff --check` passed.
- Browser-console verification is not applicable to this native macOS AppKit view. Live click/hover verification remains part of the installed-app check after merge.

## Comparison history

1. First implementation capture reviewed against the supplied reference in `/tmp/taskbar-vibe-island-comparison.png`. The warm accent, rounded dark shell, bordered cards, and compact control hierarchy are present; no P0/P1/P2 correction was needed.

## Implementation checklist

- [x] Preserve Task Bar data and interaction behavior.
- [x] Apply shared dark control-surface tokens.
- [x] Restyle header, segmented filter, task cards, empty state, and separators.
- [x] Build and render the native view.
- [ ] Merge PR, rebuild from `origin/main`, install, and visually check `/Applications/Task Bar.app`.

## Follow-up polish

- [P3] If desired, a future pass can add a user-selectable ambient backdrop treatment. It should remain optional so task text does not lose contrast against arbitrary desktop content.

final result: passed

---

# Historical QA — Model Routing Platform Button Style

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

# Historical QA — Codex / Claude model routing

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

# Historical QA — Follow Global Control

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
