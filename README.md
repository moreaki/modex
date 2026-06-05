# Modex

Modex is a small macOS monitor for local Codex token and context usage.

The first version reads local Codex JSONL session files under `~/.codex/sessions`
and `~/.codex/archived_sessions`, then reports:

- scanned session count
- token event count
- total tokens from each session's latest total
- average and median tokens per turn
- approximate latest context usage
- compaction-related event count

## Run

Print a one-shot terminal summary:

```bash
swift run modex --once
```

Scan a larger or smaller number of recent session files:

```bash
swift run modex --once --limit 100
```

Start the menu bar monitor:

```bash
swift run modex
```

The menu refreshes every 60 seconds.

## Notes

Codex session JSONL files are local implementation details. Modex treats missing
or changed fields as absent data and should stay conservative about what it
reports. It does not send data anywhere.

The current context percentage is approximate because local logs expose token
count events, not a full public per-thread context model.

By default Modex scans the 5 most recently modified session files. This keeps
the menu-bar refresh quick even when older Codex JSONL archives are very large.
