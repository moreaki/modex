# Modex

Modex is a small SwiftUI macOS menu-bar monitor for local Codex token, context, and session usage.

It reads local Codex JSONL data from `~/.codex`, keeps the menu quick with streaming scans and an in-memory scan cache, and shows the current context/rate-limit picture without sending data anywhere.

## What It Shows

- A menu-bar heartbeat gauge with the latest scanned session context percentage.
- A Codex `/status` style overview with context left plus 5h and 7d limit bars when those values are present in local logs.
- A compact per-thread table grouped by project, using Codex `thread_name` as the row title and the session id as secondary metadata.
- Per-thread context usage, model, reasoning effort, speed, total tokens, median/average turn tokens, compaction count, and last update age.
- Calm hover details for full session/project/file information and exact token values.
- Last-read instrumentation: duration, bytes read, parsed files, active/configured concurrency, parser buffers, cache hits/misses, and slowest files.

Codex JSONL schemas are local implementation details, so Modex treats missing or changed fields as absent data and keeps parsing defensive.

## Requirements

- macOS 14 or newer
- Swift 6.3 or newer

## Run

Print a one-shot terminal summary:

```bash
swift run modex --once
```

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

## Menu-Bar Reading

The number beside the menu-bar icon is the rounded context percentage used by the latest scanned Codex session:

```text
input_tokens / model_context_window * 100
```

If context usage is unavailable, Modex falls back to a compact total-token value. The circular gauge uses the configured context thresholds, with defaults of 55%, 78%, and 90%.

Clicking the menu-bar item opens immediately using the latest cached result, then refreshes in the background. The default refresh interval is 60 seconds.

## Configuration

Configuration is available from the gear button in the menu.

Defaults:

- Scan limit: 5 most recently modified active session files.
- Archived sessions: off.
- Scan cache: on.
- Refresh interval: 60 seconds.
- Read concurrency: up to 2 files at a time by default.
- Theme: System.
- Language: System.
- Row-detail hover delay: 500 ms.

General settings cover scan limit, refresh interval, archived-session inclusion, scan cache enablement, cache flushing, and the Codex data folder. Appearance settings cover System/Black theme, language, and hover delay. Context settings tune the warning thresholds. Expert settings tune parser concurrency and buffer sizes.

Settings are stored in macOS `UserDefaults` under the app domain `ch.moreaki.modex`. The parsed scan cache is intentionally in-memory only and is rebuilt after app restart.

## Data Sources

Modex scans:

- `~/.codex/sessions` by default
- `~/.codex/archived_sessions` only when archived sessions are enabled
- `~/.codex/session_index.jsonl` for thread names

It currently uses local fields such as token-count usage, model context window, rate limits, `turn_context` model metadata, compact events, working directory, session id, and thread name.

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

The next dashboard/detail-window direction is documented in `docs/dashboard-and-detail-window.md`, with a lightweight clickable prototype in `docs/prototypes/dashboard-detail-prototype.html`. The proposed history store, intelligence metrics, graph overview, and row sparklines are documented in `docs/history-intelligence-and-graphs.md`, with a graph prototype in `docs/prototypes/history-graphs-prototype.html`.
