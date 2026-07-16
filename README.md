# Modex

Modex is a small SwiftUI macOS menu-bar monitor for local Codex token, context, and session usage.

It reads local Codex data from `~/.codex`, uses Codex's read-only state index to find threads, and streams their JSONL files through an in-memory scan cache. The current context/rate-limit picture stays local unless optional Codex Intelligence is explicitly enabled.

## What It Shows

- A menu-bar heartbeat gauge with the remaining seven-day Codex account quota.
- A Codex `/status` style overview with context left plus the rate-limit windows reported by current local logs.
- A compact per-thread table grouped by project, using the indexed Codex thread title as the row title and the session id as secondary metadata.
- Separate seven-thread recent-activity views for Codex Project threads and standalone Task threads, while the complete eligible thread set progressively fills the detached detail window.
- Per-thread context usage, model, reasoning effort, service tier, source, Codex version, speed, total tokens, median/average turn tokens, compaction count, and last update age when available.
- Current activity metrics for command outcomes, patches, MCP calls, web searches, sub-agent activity, aborted turns, and changed files.
- Persistent history-backed trend cards and sparklines for context pressure, token growth, scan health, turn size, duration, and failure activity.
- A detached detail-window Insights tab with deterministic, evidence-backed signals such as high context, failed commands, slow turns, repeated compactions, high cache reuse, slow scans, and cold cache behavior.
- Calm hover details for full session/project/file information and exact token values.
- On-demand instrumentation: last-read latency, memory footprint, lifetime peak memory, CPU time, wakeups, context switches, physical I/O, parser buffers, exact-cache hits, append reuse, actual one-hour totals, and per-scan averages over the last hour.

Codex JSONL schemas are local implementation details, so Modex treats missing or changed fields as absent data and keeps parsing defensive.

## Requirements

- macOS 14 or newer
- Swift 6.3 or newer

## Run

Print a one-shot terminal summary:

```bash
swift run modex --once
```

Print the Modex application and build version:

```bash
swift run modex --version
```

Without `--limit`, the one-shot command scans every active thread. Use `--include-archived` to add archived threads or `--limit` for a deliberately bounded diagnostic run.

Useful one-shot options:

```bash
swift run modex --once --limit 20
swift run modex --once --include-archived
swift run modex --once --concurrency 4 --chunk-kb 512 --line-buffer-kb 1024 --index-line-buffer-kb 256
```

For normal menu-bar use, package and open the lightweight app bundle:

```bash
scripts/package-app.sh
open .build/Modex.app
```

Raw `swift run modex` can start the app, but the packaged bundle is the more reliable way to get a visible macOS menu-bar item.
The packaging script builds an optimized release binary by default; use `MODEX_BUILD_CONFIGURATION=debug scripts/package-app.sh` only for a deliberately unoptimized development bundle.
It obtains the semantic version and build number from the compiled executable and writes them into the packaged app bundle, keeping the GUI, CLI, and `Info.plist` aligned.

## Menu-Bar Reading

The number beside the menu-bar icon is the rounded percentage remaining in the current seven-day general Codex account-limit window. It is the same value shown by the dashboard's `7d limit` bar:

```text
100 - seven_day_limit.used_percent
```

The circular track also represents quota remaining, so it drains as the weekly allowance is consumed. Its colour becomes more urgent based on the consumed percentage, using the configured warning thresholds. When a seven-day account limit is unavailable, Modex shows a neutral icon without substituting an unrelated token or thread-context value. Highest individual thread context remains available as a separate dashboard metric.

Modex selects the newest general Codex account-limit event across all scanned sessions and ignores named model-specific limit pools. It identifies the seven-day window by its duration whether Codex reports it as the primary or secondary window, preserving compatibility with both local payload layouts. The percentage is capacity left, matching Codex's Usage & billing semantics.

Clicking the menu-bar item opens immediately using the latest cached result, then refreshes in the background. On a cold read, Modex prioritizes the seven newest Project threads and seven newest standalone Task threads, publishing rows as they become available before progressively adding every remaining eligible thread. The default refresh interval is 60 seconds.

Project versus Task classification follows Codex’s own `projectless-thread-ids` sidebar state. Modex reads that array with a bounded streaming parser and caches it by file identity; path and repository metadata are used only as a fallback when the state is unavailable.

## Configuration

Configuration is available from the gear button in the menu.

Defaults:

- Thread scope: all active threads.
- Archived sessions: off.
- Scan cache: on.
- Refresh interval: 60 seconds.
- Read concurrency: up to 2 files at a time by default.
- Theme: System.
- Language: System.
- Row-detail hover delay: 500 ms.
- Agent insights: off.

General settings cover refresh interval, archived-thread inclusion, scan cache enablement, cache flushing, and the Codex data folder. Appearance settings cover System/Black theme, language, and hover delay. Context settings tune the warning thresholds. Intelligence settings control optional Codex-assisted interpretation, local Codex executable path, timeout, test connection, and generated-insight cache flushing. Expert settings tune parser concurrency and buffer sizes.

The Intelligence settings section controls optional Codex-assisted narrative interpretation. Modex remains deterministic and local-first by default: facts, charts, sparklines, and reason-coded insights work without sending prompt text anywhere. When enabled, the Local Codex provider uses `codex exec --ephemeral` with a strict output schema and a compact metrics bundle. The connection test turns green only after a real structured insight response is validated.

A successful Intelligence test stores a small verification receipt in `UserDefaults`: provider, executable path, and verification timestamp. Relaunching restores the verified state only when the active configuration still matches that receipt. Changing the provider or executable requires a new test; failed verification invalidates the matching receipt.

Settings are stored in macOS `UserDefaults` under the app domain `ch.moreaki.modex`. The parsed scan cache is intentionally in-memory only and is rebuilt after app restart. Growing active JSONL files resume from a verified append checkpoint; rewritten or truncated files automatically fall back to a full streaming parse.

History samples are stored in a compact SQLite database at:

```text
~/Library/Application Support/Modex/history.sqlite
```

The history store contains derived scan/thread metrics, lightweight per-scan resource counters, and generated insight summaries, not raw prompt text. Successful Codex insight runs are retained as a small run history while the latest generated result stays quick to display.

Modex records the last successfully launched application version in `UserDefaults`. Ordered startup migrations run before settings and persistent stores are opened, and the recorded version advances only after every pending migration succeeds. The history database maintains a separate schema version. See [Versioning And Migrations](docs/versioning-and-migrations.md) for the release-bump and migration workflow.

## Data Sources

Modex scans:

- a compatible SQLite thread index under `~/.codex` as a read-only metadata source when available; Modex discovers it by schema rather than assuming a versioned filename or fixed subdirectory
- `~/.codex/sessions` for all active thread histories
- `~/.codex/archived_sessions` only when archived sessions are enabled
- `~/.codex/session_index.jsonl` as a legacy title fallback

Detailed metrics still come from streaming JSONL reads. Modex understands token usage, model context windows, rate limits, turn and thread settings, paired compaction records, command tool outcomes, patches, MCP and web activity, sub-agent activity, aborted turns, working directories, and session metadata. If the state database is unavailable or its schema changes, discovery falls back to the filesystem rather than failing the scan.

## Project Layout

- `Sources/modex/App`: SwiftUI app entry point and menu-bar scene.
- `Sources/modex/Models`: app settings and observable menu state.
- `Sources/modex/Services`: app controller and localization lookup.
- `Sources/modex/UI`: SwiftUI views, status icon, visual theme, and controls.
- `Sources/modex/Resources`: localized Swift Package resources.
- `Sources/ModexCore/Core`: Codex JSONL scanner and streaming parser.
- `Sources/ModexCore/Models`: session, token, summary, and scan metrics.
- `Sources/ModexCore/Services`: cached monitor and one-shot report formatter.

## Development

Run the usual checks:

```bash
swift build
swift test
git diff --check
swift run modex --once
scripts/package-app.sh
```

Lint localized strings after editing UI text:

```bash
plutil -lint Sources/modex/Resources/*.lproj/Localizable.strings
```

For menu-bar UI work, relaunch `.build/Modex.app` and inspect the actual popup in both System light/dark appearance and Black theme.

Fast relaunch loop:

```bash
scripts/package-app.sh
pkill -x Modex || true
open .build/Modex.app
```

Screenshots are useful for reviewing SwiftUI menu-bar details that are hard to judge from code alone: status icon rendering, column alignment, hover states, text clipping, focus highlights, and whether the popup shifts unexpectedly.

Parser benchmarks live in `Benchmarks/ParserComparison`. They compare the current Modex streaming parser with alternate JSON parsers without adding benchmark-only dependencies to the app target.

The reusable design and measurement lessons behind discovery, bounded concurrency, streaming memory, progressive publication, exact and append-resume caching, native process counters, and historical resource averages are documented in [Fast Concurrent Scanner Architecture](docs/fast-concurrent-scanner-architecture.md).

The next dashboard/detail-window direction is documented in `docs/dashboard-and-detail-window.md`, with a lightweight clickable prototype in `docs/prototypes/dashboard-detail-prototype.html`. The proposed history store, intelligence metrics, graph overview, and row sparklines are documented in `docs/history-intelligence-and-graphs.md`, with a graph prototype in `docs/prototypes/history-graphs-prototype.html`.
