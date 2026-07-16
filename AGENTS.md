# AGENTS.md

## Project Context

Modex is a SwiftUI macOS menu-bar monitor for local Codex session, token, context, and limit usage.

Treat it as a fast monitoring utility first. The primary UX goal is calm, immediate situational awareness from the menu bar, with richer details available only when useful.

## Architecture Guard Rails

- Keep UI and application logic separated. SwiftUI views should compose state and presentation, while parsing, scanning, caching, formatting, settings persistence, and CLI reporting live in core/services/model layers.
- Keep the CLI path working whenever app logic changes. `swift run modex --once` should continue to use the shared core behavior where practical.
- Prefer SwiftUI for all UI. Use AppKit only as a small, isolated bridge for macOS integration that SwiftUI cannot provide cleanly.
- Before adding new AppKit, evaluate whether the need is true macOS shell/window plumbing rather than UI composition. Good candidates include exact menu-bar window placement, window level/Spaces behavior, focus policy, and status-item geometry. Ask before introducing a new AppKit bridge unless the user has already approved that specific bridge.
- Keep AppKit out of SwiftUI views where practical. Put bridge code in a small service or adapter, expose an intent-focused API, and keep the SwiftUI call site minimal.
- Preserve the source layout pattern: `App`, `Core`, `Models`, `Resources`, `Services`, and `UI`.
- Preserve the scanner layer boundaries documented in `docs/fast-concurrent-scanner-architecture.md`: capability-based discovery, bounded scheduling, streaming parsing, cache/checkpoint reuse, aggregation, history, and presentation must remain independently testable.
- All visible strings belong in localized resources. Do not add hard-coded English UI strings in SwiftUI views, tooltips, menus, settings, or table headings.
- Settings should persist through `UserDefaults` via the settings store, not through scattered direct calls from views.
- Treat `ModexApplicationVersion.current` and its build number as the release source of truth. Keep CLI output and packaged `Info.plist` derived from it, and add an ordered startup migration with a fixed literal introduction version when a release requires cache invalidation or persisted-data transformation. Never register a historical migration against `.current`.
- Keep application release versions separate from persistence schema versions. Startup migrations coordinate cross-store changes; each SQLite store owns its schema migration and must reject unsupported newer schemas.

## Swift And Dependency Rules

- Target Modex as a macOS Swift Package app. Keep `Package.swift` as the source of truth for supported macOS and Swift toolchain versions.
- Use Swift 6 language mode practices: explicit isolation where useful, Sendable-aware models for cross-task data, and clear actor boundaries for UI updates.
- Prefer async/await over callback-style APIs.
- Use structured concurrency for bounded parallel work such as file scans; avoid unbounded task creation.
- Use SPM dependencies only. Avoid adding dependencies unless they clearly improve correctness, performance, or maintainability.
- Verify unfamiliar Apple or package APIs against primary documentation before introducing them.

## SwiftUI Rules

- Build UI in SwiftUI by default. Use AppKit only as an isolated bridge for macOS behavior SwiftUI cannot provide cleanly.
- Use SF Symbols for standard actions and controls unless the custom Modex status gauge or product-specific drawing is required.
- Add `#Preview` blocks for reusable visual SwiftUI components when they can be rendered with lightweight fixture data.
- Do not enforce one type per file. Keep small private view structs near the feature they support when that improves readability.

## Performance Guard Rails

- Clicking the menu-bar icon must show usable information immediately. Do not block popover presentation on a fresh scan.
- Package the normal app as an optimized release binary. Debug builds materially distort parser latency and energy measurements; use them only for deliberate debugging.
- Refresh data asynchronously and show the last known result while a new scan runs.
- Scan every eligible active thread by default, with archived threads controlled only by the archive toggle. Do not add an app-level file-count limit.
- On a cold refresh, prioritize the seven newest Project threads and seven newest standalone Task threads, publish those rows as each becomes available, and complete that priority set before publishing coalesced updates from the remaining bounded-concurrency scan.
- JSONL scanning must remain streaming and memory-conscious. Do not load large session files fully into memory.
- Keep parser code defensive; local Codex JSONL schemas are implementation details and can change.
- Prefer a compatible read-only Codex SQLite thread index for discovery and metadata. Locate databases by file type and identify the index by schema rather than hard-coding versioned filenames such as `state_5.sqlite`; retain filesystem and `session_index.jsonl` fallbacks for older or changed installations. Never read `first_user_message` or `preview` merely to label or rank threads.
- Scan concurrently, but keep concurrency configurable and visible in instrumentation.
- Implement concurrency as a refilling bounded task group with at most the configured number of live child tasks. Do not create one task per file and rely on the executor to provide backpressure.
- Keep parser memory bounded per active task. Drain Foundation temporaries per chunk with `autoreleasepool`, cap cross-chunk line storage, and never retain raw file chunks in the scan cache.
- Default to active sessions only. Archived sessions should be opt-in because they can be large and old.
- Use a small, understandable cache keyed by file identity such as path, size, and modification time. Growing append-only logs may resume from a bounded parser checkpoint only after verifying a tail fingerprint; truncation or mutation must fall back to a full parse.
- Read large auxiliary Codex state files with bounded memory and cache derived metadata by file identity. Do not decode a multi-megabyte global state document merely to obtain one small array.
- Do not write unchanged exact-cache thread snapshots to history on every refresh. Persist changed thread samples and the lightweight scan sample instead.
- Expose cache enabled/disabled, flush, exact hits, append reuse, entries, and saved bytes in instrumentation.
- Instrument facts, not guesses: duration, bytes read, files parsed, parser mode, active/configured concurrency, chunk size, line caps, oversized lines, cache behavior, slowest files, process memory, lifetime peak memory, CPU time, wakeups, physical I/O, and context switches.
- Resource counters belong behind the on-demand instrumentation action. Keep the normal dashboard calm, and label process-wide/lifetime measurements honestly.
- Prefer actual resource totals from persisted scan samples over extrapolating one scan to an hourly rate. Do not claim watts, energy impact, or whole-app power consumption without a trustworthy public measurement source; CPU time, I/O, wakeups, and context switches are factual proxies.
- Historical resource views must distinguish latest values, fixed-window totals, and per-scan averages. Weight average CPU load by total CPU time over total wall time, use completion footprints for memory averages/highs, and show the measured sample count.
- Every compact instrumentation value needs localized, aggregation-specific help. Explain the order of paired values and reveal help in a fixed area that does not resize or cover the metrics.
- Benchmark scanner changes in optimized release mode against the same corpus and equal concurrency. Compare wall time, peak memory, instructions, cycles, and context switches; benchmark cold parse, exact-cache, and append-resume paths separately.
- Make slow-file diagnostics identifiable by thread/session name where possible, not only by filename.

## Menu Bar UX

- The menu bar item should be discreet, stable, and glanceable.
- Preserve the custom circular context gauge: track, colored arc, subtle glow, and heartbeat mark. The icon is part of the product identity.
- The menu-bar number must be documented and semantically clear. Avoid ambiguous numbers without tooltip or README explanation.
- Avoid toolbar/menu morphs that change the popup width, anchor, or position after focus changes. Layout jiggle is worse than a clever transition.
- Do not make the user wait for a scan before opening the menu. Use cached state and update in place.

## Information Hierarchy

- Put global/latest Codex `/status` style information above the table, not inside per-thread table columns.
- Keep the Codex Intelligence connection state visible on the dashboard. Make an unverified, limited, disabled, or failed state a direct route to its Configuration section rather than a dead status badge.
- Keep the table for per-thread/session information only. Do not replace median/average/total token columns with global status values.
- Use the thread name as the primary row label. Use the project name for grouping. Keep the session id as secondary metadata.
- Keep Codex Project threads and standalone Task threads as separate scopes in overview and detail surfaces. Use Codex's authoritative `projectless-thread-ids` state when available; directory and repository inference is only a fallback.
- Do not show the last user prompt text in the main table. It is noisy and not needed for monitoring.
- Show model, reasoning, and speed per thread when available. Do not show fields like `Summary: auto` unless they have a clear user-facing meaning.
- Show stale update information honestly. If an update is days or weeks old, prefer relative age such as `3d ago` over a bare clock time that looks current.
- Keep compact metric-card supporting text factual and self-explanatory. Do not place an unlabeled thread title where it can be mistaken for a diagnosis; put full identifiers in hover or detail surfaces instead.
- Use hover or secondary surfaces for full paths, full session ids, file paths, exact token counts, and dense diagnostics.

## Table Design

- Design the table for scanning and comparison, not for decoration.
- Keep columns stable: thread, context, total, median, average, compactions, updated, and model-related details where space allows.
- Use fixed or predictable column widths so hover states, exact values, and animations cannot overlap neighboring values.
- Compact values are fine in the table, but exact values should be reachable through a calm reveal.
- Use a sparkline only when its samples are an honest, ordered time series and the adjacent value names the same measure. Show cumulative totals, rates, and ranked values directly instead of decorating them with unrelated or synthetic trends.
- Exact-number reveals should morph from compact to exact value only. Do not show both compact and exact values side by side, and do not wrap them in a capsule unless there is a clear reason.
- If an exact value can be wider than its column, constrain, scale, or clip it so it never shadows the next cell.
- Agent-generated insight copy must fit table rows: short title, one compact diagnosis sentence, and one compact next step. Do not let generated prose become a paragraph.
- Do not expose internal app states such as `agentUnavailable`, `Needs Codex`, or connection state names as evidence in generated insight text.
- Agent insight actions must have a legible workflow: ready, analyzing, analyzed, update available, and failed. Preserve the last successful interpretation while refreshing or after an update failure, timestamp the analysis itself, and invalidate it only for material signal changes.
- Persist successful generated insight runs append-only while also keeping the latest result fast to display.
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
- Localization files must contain real language-specific copy. Do not copy English strings into `de`, `fr`, `es`, or `it` as a placeholder except for intentional product names, code formulas, file names, format tokens, or very short technical labels that are normally unchanged in that language.
- When adding, removing, or changing a localization key, update every supported `.lproj/Localizable.strings` file in the same change. Preserve the key order across locale files so drift is easy to review.
- Preserve placeholder contracts exactly across translations: `%@`, `%d`, escaped `%%`, and `\n` must remain present and in the same semantic order.
- Before finishing localization work, compare non-English files against `en.lproj` for suspicious copied sentence-length English values and fix them rather than leaving fallback text for later.
- Verify both System and Black themes, and verify light and dark appearances when System is selected.

## Verification

After completing a user request that changes project files, stage the intended
changes, create a descriptive commit, and push the current branch unless the
user explicitly asks not to. Do not create empty commits or include unrelated
user changes merely to satisfy this workflow.

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
