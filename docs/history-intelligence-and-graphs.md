# History, Intelligence, And Graphs

This note captures the next layer for Modex after the dashboard/detail-window prototype: persisted history, graph-driven overview, row sparklines, and useful derived signals about how productively a Codex thread is using context and tokens.

## Why Persist History

The current app is mostly a latest-scan monitor. That is fast and useful, but it cannot answer trend questions unless it reparses old files or keeps its own small history.

Persisted history should answer:

- Which threads are climbing toward context limits fastest?
- Which threads repeatedly compact, stall, or fail commands?
- Which sessions are using many tokens without producing visible work?
- Which model/reasoning/speed combinations are efficient for this project?
- Is Modex scanning quickly because the cache is effective, or because little changed?
- Are old archived sessions affecting current interpretation?

History should not make the menu slow. The menu opens from cached state, a background scan writes a compact snapshot, and charts read small aggregate rows rather than huge JSONL files.

## Storage Direction

Use a small native SQLite database in Application Support for Modex-owned snapshots. The JSONL files remain the source of truth; SQLite stores derived observations so the UI can draw trends quickly.

Candidate tables:

- `scan_samples`
  - timestamp
  - duration
  - bytes read
  - files considered
  - files parsed
  - cache hits/misses
  - saved bytes
  - configured and active concurrency
  - parser settings
- `thread_samples`
  - timestamp
  - session id
  - thread name
  - project path/name
  - archived flag
  - context used/window/percent
  - total tokens
  - median/average turn tokens
  - compactions
  - model
  - reasoning
  - speed
  - command/tool/file-change counts
  - failed command count
  - cached input ratio
  - reasoning output ratio
  - last turn duration
  - median turn duration
  - time to first token
- `status_samples`
  - timestamp
  - context used/window/left percent for latest active session
  - 5h limit left/reset
  - 7d limit left/reset
- `thread_identity`
  - session id
  - latest thread name
  - project path/name
  - source JSONL path
  - first seen
  - last seen

Retention should be modest and explainable. Keep raw per-scan samples for recent history, then roll up older data hourly/daily if the database starts to grow. Do not store prompt text as part of the history store.

## SQLite Layer Spike

[`pointfreeco/sqlite-data`](https://github.com/pointfreeco/sqlite-data) is worth exploring, but it should not be adopted blindly.

Why it is interesting:

- It is positioned as a fast, lightweight SwiftData replacement powered by SQL.
- It builds on GRDB and StructuredQueries, which fits an app that wants explicit SQL, indexes, and aggregate queries.
- Its SwiftUI observation model could make detail-window graphs and filters feel native without hand-rolled invalidation.
- Its README claims performance close to SQLite C APIs for decoded query results.

Why it may be overkill:

- Modex only needs a local append-only metrics store at first.
- The package brings a larger dependency surface than direct `sqlite3`, including GRDB and several Point-Free support libraries.
- CloudKit/sync-style capabilities are not needed for Modex history.
- The CLI should stay simple and should not become coupled to UI observation machinery.

Spike criteria:

- Add it behind a `HistoryStore` protocol, not directly inside SwiftUI views.
- Compare a tiny direct-`sqlite3` implementation with SQLiteData for schema setup, inserts, aggregate queries, migrations, binary size, cold-start cost, and build complexity.
- Keep write paths batched. One scan should insert/update in a short transaction.
- Keep reads graph-oriented: fetch only the points needed for visible ranges and sparklines.
- Reject any layer that makes `swift run modex --once` slower, fragile, or awkward to package.

Recommended default for the first implementation: start with a narrow `HistoryStore` interface and a small direct SQLite or GRDB-backed implementation. Try SQLiteData in a branch if the detail window needs reactive queries, richer filtering, or cleaner model observation.

## Graph Components

### Dashboard Overview

The dashboard should show history as calm signals, not as a mini analytics product.

Useful components:

- `ContextPressureChart`
  - multi-thread trend for the top watched threads
  - context percent over time
  - threshold bands for yellow/orange/red
- `LimitHistoryPanel`
  - 5h and 7d left over time
  - reset markers
  - current Codex `/status` bars remain primary
- `TokenEconomyPanel`
  - cached input ratio
  - reasoning output share
  - tokens per completed turn
  - tokens per useful activity proxy
- `ScanHealthPanel`
  - scan duration trend
  - bytes read
  - cache hit ratio
  - changed files per scan
- `AttentionTrend`
  - top five threads ranked by current risk plus recent change
  - each row shows why it is ranked

### Table And Row Sparklines

Small sparklines should support comparison without adding visual noise.

Good cells for sparklines:

- context column: recent context percent shape
- total column: token growth
- average/median columns: recent turn-size trend
- updated/activity column: recent activity pulses
- failure/activity column in detail view: failed command bursts

Rules:

- Sparklines must fit fixed column widths and never push text into neighboring cells.
- Use one calm stroke color per semantic state, not random per-thread colors.
- Show exact values on hover or detail surfaces, not in the sparkline itself.
- Use sparklines for direction and volatility, not as precise charts.
- In the detail window, prefer sparklines directly inside table cells for context, token growth, turn size, turn duration, failed command bursts, changed-file activity, scan duration, and cache hit-rate.
- Keep sparkline dimensions stable across rows in the same column. Missing history should render as an empty quiet placeholder, not collapse the cell.

### Detail Window Graphs

The detached detail window can be more analytical:

- per-thread timeline with context, compactions, failures, and model changes
- token split graph: input, cached input, output, reasoning output
- command/tool/file-change timeline
- latency graph: time to first token, last duration, median duration
- scan diagnostics graph: slowest files, oversized lines, cache savings
- project comparison view: threads grouped by project with aggregate totals and risk

### Insights Table

Insights should be a first-class detail-window tab or table, not a set of scattered cards. Treat it as an auditable queue of things worth attention.

Rows can be created from:

- deterministic signal engine rules
- user-triggered metric insight actions
- agent-generated interpretations when connectivity is green

Suggested row fields:

- id/fingerprint
- severity or state
- metric/source
- thread id and project
- deterministic reason code
- concise title
- agent summary when available
- confidence
- evidence ids and counts
- source sample/log fingerprint
- signal-updated and analysis-generated timestamps
- suggested next action

The table should support filtering by project, metric type, severity, analysis state, and thread. A metric insight icon in a table cell should jump to the matching Insights row or create one by running analysis.

## Intelligent Signals

These signals must be framed as heuristics. Modex can infer patterns from local logs, but it should not pretend to know whether the human task was actually solved unless the data proves it.

Separate three layers:

- Facts: values directly observed or derived from local data, such as context percent, tokens, compactions, command failures, changed files, cache ratio, scan duration, and model metadata.
- Deterministic signals: small explainable rules over facts, such as "context rising quickly", "many failed commands", "cache reuse high", "stale for 3d", or "slowest recent turn". These are safe to compute locally because they are auditable and do not claim intent.
- Agent interpretation: narrative conclusions such as "good reuse", "watch friction", "entropy reduction improved", or "likely productive". These should only be shown when Modex has explicit access to a running/local Codex agent or a configured model endpoint.

Without agent access, Modex should show facts, trends, scores, and terse deterministic reasons. It should not show polished interpretive prose that looks like an analyst read the session.

### Agent-Assisted Interpretation

Narrative insight panels should be optional and gated behind a clear capability check.

Acceptable sources:

- a local/running Codex agent interface exposed to Modex
- a user-configured API token/model endpoint
- a future Codex-supported local analysis command

Rules:

- Keep it opt-in and visible in Settings.
- Never block menu opening or normal scan refresh on agent analysis.
- Send compact derived metrics and event summaries, not raw prompt text by default.
- Ask for structured output with fields such as title, summary, confidence, severity, and evidence ids.
- Display evidence-backed snippets like metric names, timestamps, session ids, and counts so the user can verify the claim.
- Mark an update as available only when the material signal fingerprint changes after analysis; ordinary timestamps and unrelated activity must not invalidate useful output.
- Provide a deterministic fallback: show the underlying facts and reasons if agent access is unavailable.
- Avoid "solved", "successful", or "useful" claims unless explicit evidence supports them.

Implemented shape:

- `ModexHistoryStore` persists scan/thread samples, graph points, and generated insight summaries.
- `ModexSignalEngine` computes deterministic facts, trends, thresholds, and attention reasons.
- `LocalCodexAgentInsightService` is optional and consumes only summarized signal bundles through `codex exec --ephemeral`.
- SwiftUI renders deterministic insight rows immediately and can enrich a row with a schema-validated Codex result on demand.

The app should avoid hard-coding lots of prose-based interpretation. Hard-code metric definitions, thresholds, and reason codes; let an optional agent turn those facts into natural-language summaries when configured.

### Codex Connectivity Settings

Agent interpretation needs a first-class settings surface. It should not be hidden in parser expert settings because it changes what Modex can infer and may involve credentials.

Settings should include:

- enabled/disabled toggle for agent-assisted insights
- provider/source selector:
  - none/off
  - local/running Codex agent when available
  - Codex CLI or future local analysis command
  - configured API token/model endpoint
- configurable local Codex executable or command path
- timeout for local insight requests
- credential state without revealing secrets
- model or capability summary when known
- "Test Connection" action
- last test result with timestamp
- last successful prediction test with timestamp
- failure reason when disconnected
- privacy option to send metrics only by default, with raw prompt/text opt-in if ever needed

Connection states:

- Off: agent insights disabled; deterministic facts and signals still work.
- Unknown: configured but not tested yet.
- Testing: transient state while the test runs.
- Connected: the source is reachable and can produce a structured sample insight from a tiny synthetic metrics bundle.
- Limited: reachable, but missing a capability needed for narrative insight.
- Failed: unreachable, unauthorized, timed out, or returned invalid structured output.

The green state means more than "a token exists". It means Modex successfully completed a tiny end-to-end test:

1. build a synthetic signal bundle with no private prompt text
2. call the configured Codex/agent provider
3. receive structured output with title, summary, confidence, severity, and evidence ids
4. validate the response shape
5. store the status and timestamp

The test must run asynchronously, must be cancellable, and must never block opening the menu. If a later insight update fails, Modex should preserve the last successful interpretation, identify the update failure, and keep the deterministic signal available.

UI guidance:

- Put the connection control in Settings as a calm "Codex Intelligence" or "Agent Insights" section.
- Use a green status dot or pill only for the verified end-to-end connected state.
- Keep the test action explicit; do not test repeatedly on every menu open.
- Show the last test time and short failure reason.
- Keep deterministic graphs visible even when disconnected.

### Metric Insight Actions

Some factual metrics should expose an optional insight action. Failed command stats are the clearest first case: the raw number is useful, but the user often wants to know whether failures are harmless exploration, repeated environment issues, permission problems, flaky tests, missing tools, or a real blocker.

Behavior:

- Show a small insight icon next to eligible metrics such as failed commands, failure-cost proxy, slowest turn, repeated compactions, or unusual context growth.
- Enable the icon when Codex Intelligence is configured. Prefer a disabled state with a short "Connect Codex Intelligence in Settings" explanation when the provider is off.
- The action must be user-triggered. Do not automatically send logs to an agent just because a metric is visible.
- Send the smallest useful bundle: command summaries, exit codes, timestamps, thread/session ids, surrounding deterministic metrics, and selected log excerpts only when explicitly allowed later.
- Avoid raw prompt text by default. If deeper log text is needed, ask for explicit opt-in or use a privacy setting that clearly allows it.
- Ask the agent for structured output: likely cause, confidence, evidence ids, suggested next action, and whether the pattern looks transient, environmental, or blocking.
- Display the result in the detail-window `Insights` table, with evidence links back to the facts. A tiny inline result can be acceptable immediately after clicking, but the durable home is the Insights table.
- Cache the result against a material signal fingerprint. Routine timestamps, healthy command activity, and refresh bookkeeping must not invalidate an interpretation. If material evidence changes during a run, reconcile it automatically once; otherwise show the existing result as having an update available.

Current privacy boundary:

- No raw prompt text is sent.
- No raw JSONL lines are sent.
- Failed-command evidence is capped and sanitized to command executable name plus exit code.
- Generated results are persisted by insight id and metric fingerprint for fast display, and every successful generated run is also appended to a small run history. Previous results remain visible while an update runs or fails, with a clear analysis timestamp and confidence.
- Generated copy must be compact enough for the Insights table: a 2-5 word title, one short diagnosis sentence, and one concrete next step. Internal app states such as `agentUnavailable` or connection labels are not user-facing evidence and must not appear in generated prose.

For failed commands, useful evidence includes command name, exit code, duration, stderr/stdout excerpt policy, repetition count, last occurrence, surrounding model/reasoning/speed, project, thread id, and whether a later command succeeded.

### Token Economy

Question: how much useful work appears to be produced per token spent?

Candidate metrics:

- cached input ratio
- reasoning output ratio
- total tokens per completed turn
- total tokens per changed file
- total tokens per successful command
- context growth per turn
- compaction frequency per million tokens

Useful dashboard copy:

- "High cache reuse"
- "Heavy reasoning share"
- "Large token growth with little activity"
- "Efficient recent turns"

### Entropy Reduction

Question: is the session becoming clearer and more compressed, or is it accumulating unresolved complexity?

Candidate metrics:

- context recovered after compaction
- context growth rate before/after compaction
- repeated failures after compaction
- declining command failures across recent turns
- fewer tool calls needed per successful change
- stable model/reasoning settings across a thread

Possible interpretation:

- Good entropy reduction: compaction lowers context pressure and later turns remain productive.
- Poor entropy reduction: compaction happens, but failures or context growth immediately return.
- Unknown: no compactions or insufficient history.

These interpretations are agent-facing language. The deterministic UI should instead expose the measured components: context recovered, context regrowth, failure count before/after, and number of turns since compaction.

### Usefulness To The End User

Question: is this thread helping the user move toward an outcome?

Possible local proxies:

- successful shell commands
- changed files
- tests run after changes
- fewer failed commands over time
- recent activity after a long pause
- PR/branch/git metadata if available
- user continuing the same thread rather than abandoning it

Avoid claiming "solved" unless there is explicit evidence. Prefer language like "productive signals", "friction", "activity", and "likely useful".

### Efficiency

Question: how expensive is progress in time and tokens?

Candidate metrics:

- time to first token
- total turn duration
- median/average duration
- tokens per minute
- command failure rate
- tool calls per changed file
- context percent gained per completed turn
- scan time and cache savings for Modex itself

### Attention Score

The dashboard can rank threads by attention, but every score should be explainable.

Inputs:

- current context usage
- context growth trend
- update recency
- failed commands
- slow recent turn
- compaction count
- high token total only as a secondary factor

Every ranked item should expose short reasons such as "85% context", "fast growth", "17 failed commands", or "stale 3d".

## Visual Guard Rails

- Graphs should be quiet first and explanatory second.
- Use threshold bands sparingly. They help context charts but can overwhelm every panel.
- Prefer fewer, well-labeled graphs over many tiny decorative charts.
- Keep overview charts large enough to read at menu-popover distance.
- Use row sparklines only where they answer "is this rising, falling, spiky, or calm?"
- Context-growth leaders use one measure throughout: each point is the non-negative change in input-context tokens between consecutive token-count events, and the adjacent value is the latest such change. Do not pair an absolute context value with a cumulative-total sparkline.
- Performance leaders use actual turn timing events: each point is one recent completed-turn duration, and the adjacent value is the latest duration. Aggregate medians are calculated across all measured events in the current scope, never as a median of per-thread medians or repeated scan snapshots.
- Activity leaders do not use sparklines. Show failed and total command counts with the directly derived session failure percentage; rank by failed-command count so impact and rate remain distinct and readable.
- Show exact values in hover/detail surfaces.
- Keep light and black themes equally polished.
- Never let graph labels, row values, or hover reveals overlap.

## Prototype

A dependency-free graph prototype lives at:

`docs/prototypes/history-graphs-prototype.html`

It is intentionally static fake data. Use it to review graph hierarchy, spacing, row sparklines, and the kinds of intelligent signals Modex should surface before implementing the persistent store.
