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
