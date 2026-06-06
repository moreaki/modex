# AGENTS.md

## Project Context

Modex is a SwiftUI macOS menu-bar monitor for local Codex session, token, context, and limit usage.

Treat it as a fast monitoring utility first. The primary UX goal is calm, immediate situational awareness from the menu bar, with richer details available only when useful.

## Architecture Guard Rails

- Keep UI and application logic separated. SwiftUI views should compose state and presentation, while parsing, scanning, caching, formatting, settings persistence, and CLI reporting live in core/services/model layers.
- Keep the CLI path working whenever app logic changes. `swift run modex --once` should continue to use the shared core behavior where practical.
- Prefer SwiftUI for all UI. Use AppKit only as a small, isolated bridge for macOS integration that SwiftUI cannot provide cleanly.
- Preserve the source layout pattern: `App`, `Core`, `Models`, `Resources`, `Services`, and `UI`.
- All visible strings belong in localized resources. Do not add hard-coded English UI strings in SwiftUI views, tooltips, menus, settings, or table headings.
- Settings should persist through `UserDefaults` via the settings store, not through scattered direct calls from views.

## Performance Guard Rails

- Clicking the menu-bar icon must show usable information immediately. Do not block popover presentation on a fresh scan.
- Refresh data asynchronously and show the last known result while a new scan runs.
- JSONL scanning must remain streaming and memory-conscious. Do not load large session files fully into memory.
- Keep parser code defensive; local Codex JSONL schemas are implementation details and can change.
- Scan concurrently, but keep concurrency configurable and visible in instrumentation.
- Default to active sessions only. Archived sessions should be opt-in because they can be large and old.
- Use a small, understandable cache keyed by file identity such as path, size, and modification time. Expose cache enabled/disabled, flush, hits, misses, entries, and saved bytes in instrumentation.
- Instrument facts, not guesses: duration, bytes read, files parsed, parser mode, active/configured concurrency, chunk size, line caps, oversized lines, cache behavior, and slowest files.
- Make slow-file diagnostics identifiable by thread/session name where possible, not only by filename.

## Menu Bar UX

- The menu bar item should be discreet, stable, and glanceable.
- Preserve the custom circular context gauge: track, colored arc, subtle glow, and heartbeat mark. The icon is part of the product identity.
- The menu-bar number must be documented and semantically clear. Avoid ambiguous numbers without tooltip or README explanation.
- Avoid toolbar/menu morphs that change the popup width, anchor, or position after focus changes. Layout jiggle is worse than a clever transition.
- Do not make the user wait for a scan before opening the menu. Use cached state and update in place.

## Information Hierarchy

- Put global/latest Codex `/status` style information above the table, not inside per-thread table columns.
- Keep the table for per-thread/session information only. Do not replace median/average/total token columns with global status values.
- Use the thread name as the primary row label. Use the project name for grouping. Keep the session id as secondary metadata.
- Do not show the last user prompt text in the main table. It is noisy and not needed for monitoring.
- Show model, reasoning, and speed per thread when available. Do not show fields like `Summary: auto` unless they have a clear user-facing meaning.
- Show stale update information honestly. If an update is days or weeks old, prefer relative age such as `3d ago` over a bare clock time that looks current.
- Use hover or secondary surfaces for full paths, full session ids, file paths, exact token counts, and dense diagnostics.

## Table Design

- Design the table for scanning and comparison, not for decoration.
- Keep columns stable: thread, context, total, median, average, compactions, updated, and model-related details where space allows.
- Use fixed or predictable column widths so hover states, exact values, and animations cannot overlap neighboring values.
- Compact values are fine in the table, but exact values should be reachable through a calm reveal.
- Exact-number reveals should morph from compact to exact value only. Do not show both compact and exact values side by side, and do not wrap them in a capsule unless there is a clear reason.
- If an exact value can be wider than its column, constrain, scale, or clip it so it never shadows the next cell.
- Column title help should explain what the metric means, but the hover itself should be quiet and non-invasive.

## Hover And Tooltip Behavior

- Use hover for supplemental detail, not for primary information required to operate the app.
- Prefer calm, delayed, lightweight detail reveals over large system tooltip balloons.
- Make row-detail hover delay configurable.
- Cancel delayed hover work when the pointer leaves, and hide hover state on focus loss.
- Tooltips and popovers must work in both light and dark themes with readable contrast.
- Preserve useful row-detail hover content: thread, project, session id, model, reasoning, speed, context used, median turn, average turn, and source file.
- Avoid oversized pointer callouts that cover the content the user is inspecting.

## Settings UX

- Settings should feel like a native, calm macOS configuration surface, not a debug panel.
- Keep the main settings tabs clear: General, Appearance, Context, and Expert.
- If agent-assisted insight is added, expose Codex connectivity as a clear settings section with enablement, provider/source, credential state, privacy mode, test action, last-tested timestamp, and readable connection state. A green state must mean an end-to-end structured insight test succeeded, not merely that a token or executable was found.
- Put uncommon parser and buffer tuning behind Expert.
- Prefer controls that match intent:
  - segmented controls or chips for small exclusive choices
  - toggles for binary settings
  - sliders with editable values for numeric ranges
  - buttons only for explicit actions such as refresh, flush cache, or quit
- Numeric sliders should have equal track lengths within the same section.
- Similar rectangular controls should have the same width when they appear as peers.
- Editable numeric values should allow typing and slider adjustment.
- Do not show a value edit box by default. Reveal the affordance on hover or while editing.
- Once editing begins, keep the edit boundary visible until commit, debounce completion, focus loss, or pointer exit.
- Clear text selection and focus highlight when editing ends or the popup loses focus.
- Avoid odd slider artifacts such as dotted underlines, stray text selection, or inconsistent border thickness.
- A language selector should be flat, quick, and readable. Show both flag and language label when space allows.
- Theme selection must include System/Default and Black. System should honor macOS light/dark mode.
- Destructive or terminal actions should use clear icons and labels. Quit/exit should not look like a generic close button for the current panel.

## Visual Style

- Calm beats clever. Use restraint, alignment, and spacing before adding decoration.
- The app should feel like a polished utility: dense enough to be useful, quiet enough to leave open.
- First-pass dashboard and popover designs must include real breathing room from the start. Rounded menu-bar windows need generous outer inset, comfortable top/title clearance, and enough bottom padding that the footer never feels clipped or pinned to the edge.
- Do not pack every region edge-to-edge just because the content fits. Prefer a slightly larger popover with calm spacing over a compact surface that makes cards, rows, chips, or toolbar icons feel pressed against the glass.
- Dense information surfaces still need hierarchy through whitespace: summary cards, status bars, insight chips, table rows, and footers should have visibly separate bands with consistent vertical rhythm.
- Avoid noisy cards, nested cards, large rounded blocks, and ornamental backgrounds.
- Use a harmonious threshold palette. Warning colors should escalate without looking random or harsh.
- Keep light and dark themes equally designed; do not treat light mode as an afterthought.
- Text must never overlap, clip awkwardly, or escape its intended area.
- Align peer controls precisely. Small width mismatches are visible in a settings UI.
- Use subtle animation only when it improves continuity. Remove animations that cause reflow, popup repositioning, or delayed comprehension.

## Accessibility And Localization

- Do not rely on color alone for meaning where text or shape can clarify the state.
- Keep hit targets comfortable for menu-bar and popup use.
- Provide useful labels/tooltips for icon-only actions.
- All new UI text must be localized in every supported language resource.
- Verify both System and Black themes, and verify light and dark appearances when System is selected.

## Verification

Before finishing UI or app behavior changes, run the relevant checks:

```bash
swift build
swift test
git diff --check
swift run modex --once
scripts/package-app.sh
```

For menu-bar UI changes, use the packaged app for the fast edit-check loop because raw `swift run modex` can be unreliable for visible menu-bar UI:

```bash
scripts/package-app.sh
pkill -x Modex || true
open .build/Modex.app
sleep 1
pgrep -x Modex
```

Inspect the real menu-bar popup after relaunch. Do not rely only on code review for layout-sensitive SwiftUI changes.

Use screenshots as visual verification artifacts when changing the menu, settings, hover states, table columns, theme colors, or status icon. Capture the actual popup state after opening the relevant panel or hover target, then check for alignment, equal peer-control widths, text clipping, overlap, unintended focus highlights, popover position, hover delay, layout jiggle, and light/dark contrast.

When changing localized resources, lint the `.strings` files:

```bash
plutil -lint Sources/modex/Resources/*.lproj/Localizable.strings
```
