# Dashboard And Detail Window

This is the next UI direction for Modex: keep the menu-bar popover calm and immediate, then move deeper investigation into a larger detached SwiftUI window.

## Product Goal

Modex should answer two different questions with two different surfaces:

- Dashboard: what is happening right now, and is anything worth attention?
- Detail window: why is it happening, and which thread/session caused it?

The Dashboard should open instantly from cached state. It must not wait for a fresh scan. The detail window can be wider, searchable, sortable, and more information dense.

## Dashboard Popover

The menu-bar popover should become a dashboard instead of a compact table.

Components:

- `DashboardHeader`
  - app icon, title, last updated, scan duration, active/archived scope
  - a stable button to open the detached detail window
- `GlobalStatusPanel`
  - active thread count
  - total scanned tokens
  - highest context usage
  - average context usage
  - scan/cache state
- `LimitUsagePanel`
  - Codex `/status` style 5h and 7d bars
  - reset time
  - optional recent trend when enough data exists
- `InsightStrip`
  - short computed signals such as highest context, fastest growth, cache ratio, failed commands, slowest turn
- `TopThreadsPanel`
  - top five threads ranked by useful attention, not just newest
  - each row shows thread name, project, model, reasoning, context, token summary, cached ratio, failed command count, and update age
- `DashboardActionBar`
  - refresh
  - timings
  - open detail window
  - settings
  - quit

The dashboard should avoid a dense table. It should use small grouped panels, predictable alignment, and calm warning color.

## Top Thread Ranking

Rank top threads by a score that favors immediate usefulness:

- high current context usage
- recent activity
- fast context growth
- failed commands
- slow or stalled recent turn
- large token total only as a secondary factor

This prevents the dashboard from becoming a list of old large sessions.

## Detached Detail Window

The detail window should be the analytical surface.

Components:

- `ThreadsWindow`
- `ThreadsWindowHeader`
- `ThreadScopeToolbar`
- `ThreadDetailTabs`
- optional `ThreadInspectorPanel`

Tabs:

- Overview: stable per-thread table with thread, project, context, total, median, average, model, reasoning, updated
- Tokens: context used/left, token splits, cached input ratio, growth per turn, compactions, projected turns until warning
- Performance: last duration, median duration, time to first token, slowest turn, tool-heavy turns, model/speed information
- Activity: shell commands, failed commands, files changed, tool calls, browser/MCP activity, git branch and commit
- Insights: dedicated table for deterministic signals and optional Codex-generated interpretations, with evidence, confidence, status, and timestamps
- Diagnostics: scan duration, cache hits/misses, bytes saved, active/archived split, parser settings, slowest files, oversized lines

### Detail Tables And Sparklines

Use sparklines inside detail tables where trend shape improves comparison:

- Overview/context: recent context percent sparkline plus current percent
- Tokens/total: token growth sparkline
- Tokens/median and average: recent turn-size sparklines
- Performance/duration: turn duration and time-to-first-token sparklines
- Activity/failures: failed command burst sparkline
- Activity/files: changed-file activity sparkline
- Diagnostics/scan: scan duration and cache hit-rate sparklines

Sparklines should sit inside fixed-width cells and never resize the table. They are trend hints, not exact charts; exact values remain available through hover or row detail.

### Insights Table

Insights should live primarily in a separate detail-window table/tab, not as scattered prose cards in the dashboard.

Suggested columns:

- Severity or state
- Metric/source, such as failed commands, context growth, compactions, slow turns, token economy
- Thread/project
- Deterministic reason code
- Agent status: offline, queued, fresh, stale, failed
- Confidence, when agent-generated
- Evidence count
- Last analyzed
- Suggested next action, if available

Metric insight icons in other tables should act as entry points:

- If the insight already exists, jump to the matching row in `Insights`.
- If Codex connectivity is green, offer to run or rerun the analysis.
- If disconnected, show the deterministic reason and a link to Settings.

The dashboard may show only a small count or short strip of top deterministic signals. It should not become the home for long narrative interpretations.

## Settings Additions

Agent-assisted interpretation should be configurable in Settings as an explicit "Codex Intelligence" or "Agent Insights" section. It should include provider/source selection, enablement, credential state, privacy mode, and a "Test Connection" action.

The test should turn the connection state green only after a tiny end-to-end structured prediction succeeds. Merely finding a token or executable is not enough. When disconnected, Modex should continue to show facts, charts, deterministic reason codes, and sparklines, but hide narrative insight panels.

Per-metric insight actions can appear where interpretation would be useful, especially failed command stats. These actions should be explicit icon buttons and should only be enabled when Codex connectivity is green. Clicking one sends a compact evidence bundle to Codex for structured analysis and shows the interpretation near the metric or in the detail-window `Insights` area.

## Data Sources

Prefer lightweight metadata first:

- `state_5.sqlite` for thread title, cwd, archived state, git metadata, model, reasoning effort, tokens used, preview, timestamps
- `session_index.jsonl` for thread id, thread name, updated time
- JSONL rollout files for exact token progression, turn timing, tool calls, file changes, command exits, compactions, limits
- `models_cache.json` for display names, context windows, speed tiers, supported reasoning levels
- `config.toml` for defaults and enabled capabilities

Keep parser behavior defensive because Codex local data schemas are implementation details.

## Suggested New Metrics

Dashboard candidates:

- active threads
- highest context usage
- average context usage
- fastest context growth
- current 5h and 7d limit left
- cache hit ratio
- failed commands
- slowest recent turn

Thread/detail candidates:

- turn count
- last turn duration
- time to first token
- median turn duration
- cached input ratio
- reasoning token share
- command/tool count
- failed command count
- changed file count
- git branch and commit
- context growth per turn
- projected turns until warning threshold

Instrumentation candidates:

- scan duration
- bytes read
- files scanned
- active vs archived bytes
- cache hits/misses
- cache entries
- saved bytes
- parser mode
- configured and active concurrency
- chunk and line-buffer caps
- oversized lines
- slowest files with thread name

## UX Guard Rails

- The Dashboard opens immediately from last known data and refreshes in place.
- The Dashboard is for decisions, not investigation.
- The detail window is for investigation, sorting, filtering, and exact values.
- Do not show last user prompt text in the Dashboard.
- Keep row labels as thread names, with project names as grouping/context.
- Keep hover details supplemental and delayed.
- Avoid layout morphs that move the popover anchor.
- Keep all text localized in the SwiftUI implementation.

## Prototype

A dependency-free clickable prototype lives at:

`docs/prototypes/dashboard-detail-prototype.html`

Open it directly in a browser. It is not production code and should not be copied into the SwiftUI implementation. Use it to review layout, hierarchy, density, color, and navigation flow.

The history, intelligence, and graph direction is documented separately in:

`docs/history-intelligence-and-graphs.md`

It includes the proposed snapshot store, SQLite layer spike, graph components, row sparklines, and heuristic metrics such as token economy, entropy reduction, usefulness, and efficiency. Its visual prototype lives at:

`docs/prototypes/history-graphs-prototype.html`
