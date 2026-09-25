# Current Codex compatibility — 0.1.7

## Account overview follow-up — 0.1.7

The account summary and secondary detail surface now expose the reported plan tier, credit balance, quota countdowns, and each returned available reset's expiration. The existing one-minute account read requests full reset details rather than count-only data; no additional request, timer, process, persistence format, or purchase/redemption action is added. Count-only notifications retain known rows while the count is unchanged, and invalidate them when it changes. Null, empty, and capped detail lists remain distinct. Unknown reset statuses are not presented as available. Price, billing provider, and reset history are unavailable through this endpoint and are explicitly identified as such.

Protocol reference: [Codex App Server rate limits](https://learn.chatgpt.com/docs/app-server#6-rate-limits-chatgpt).

Build, all 52 tests, CLI reporting, release packaging, localization lint, cross-locale placeholder/key checks, and whitespace checks pass. The live CLI returned the plan, zero credit balance, and all three reset expiration dates shown in the reference usage screen. Actual packaged dashboard/account-popover screenshots were inspected in System light and Black, including all three expirations and the scrollable footer; the Tokens detail window was inspected in System light and dark. No overlap or unreadable contrast was observed in those states. The original Modex System theme and macOS Light appearance were restored after verification.

## Original compatibility scope

Implements the core scope of issues #3–#8. Uses the installed CLI's generated App Server schema rather than a hard-coded model catalog. No new dependency, AppKit bridge, persistence schema, background daemon, or token-consuming reset action is introduced.

## Boundaries and deliberate omissions

- Local streaming scans remain independent of network/account reads. Metadata never gates first paint or the priority thread batch.
- Account availability is tri-state; neither spare reset credits nor a low window percentage implies ordinary usage is allowed. Sparse notifications merge non-null fields, preserving explicit false values. Full reads replace the snapshot.
- Account data is memory-only, dated, and invalidated on account/binary identity changes. Limits/thread lists use a 60-second TTL; analytics a 15-minute TTL, including failed attempts. Successful analytics survive later request failures without receiving a newer observation time.
- One persistent stdio connection handles bounded requests and framed responses. It waits for initialize before sending initialized/read requests. It has no polling loop or reconnect timer. Retry is demand-driven with bounded backoff; uncertain requests are never replayed. Messages are capped at 4 MiB, pending requests at 16, read chunks at one in flight with pipe backpressure, and notifications at 32 per subscriber. Framing scans each byte once, including large messages. A notification gap invalidates derived metadata.
- Thread lists use state-database-only discovery, explicit source kinds, pagination, and separate active/archive queries. Partial pages never replace the last complete result. Transient status expires and is never inferred from rollout timestamps.
- A private stdio server does not know the runtime state of desktop-owned threads. `notLoaded` and unknown statuses therefore make **no idle claim**. No compatible daemon control socket was present on this machine; Modex does not start one. This remains a protocol/runtime-scope limitation, not a fallback to guessed activity.
- Canonical SQLite name/project/originator/history/pinning fields are optional; older schemas retain their existing fallbacks. Structured subagent source metadata supplies parent IDs. Neither `preview` nor `first_user_message` is read to label or rank rows.
- Visible analytics are lifetime tokens, peak daily tokens, and exact dated daily buckets, separate from local totals. Streaks, decorative sparklines, speculative cost estimates, and redundant scan-health/dashboard history cards are omitted. Optional per-thread billing estimates are not requested.
- Model upgrades are user-selected, require an advertised target, and reset effort/speed through the existing supported-default path. Existing connection receipts consequently invalidate through their configuration identity. A missing explicit model stays visible rather than silently migrating.
- Parser deduplication retains the most recent 2,048 operation IDs and category bits per file; pending command/patch results are capped at 256 each. Duplicate lifecycle records outside that bounded window cannot be guaranteed to deduplicate. State is carried in append checkpoints, never persisted as raw logs.
- Valid legacy token counts remain authoritative. Usage-record-only logs are supported, null token-count notifications do not suppress fallback, and matching usage records enrich cache-write tokens without doubling totals. Unknown context stays unknown.

## Verification

The test suite includes old-schema history reopening, scanner priority/concurrency/cache behavior, current and mixed rollout activity, usage fallback, canonical index fields, sparse account merges, null/ordered analytics, model retirement metadata, runtime staleness rules, protocol initialization/concurrency/notifications, pagination/TTL, cancellation, malformed/oversized messages, executable replacement, backoff, and account startup announcements.

The live installed CLI smoke check decoded account availability, 166 reported daily buckets, and 112 paginated thread summaries without a reconnect. A 3 MB valid-response regression test covers pipe backpressure independently of the oversized-message rejection test. CLI reports preserve authoritative `account.ordinaryUsageAllowed` and read-only reset-credit/spend metadata using protocol field labels.

Initial 0.1.6 verification on 2026-09-25: `swift build`, all 51 tests, `swift run modex --once`, release packaging, `git diff --check`, all five localization lints, and cross-locale key/placeholder checks passed. Initial screenshot coverage was System light; the additional account and theme checks completed with 0.1.7 are recorded above.

Release-mode scanner comparison on this Mac, four concurrent parsers, identical generated 24-file / 117,210,446-byte corpus (72,000 token samples plus tool calls/outputs and matching usage records):

| Path | Before scan | After scan | Before / after scan CPU | Before / after peak footprint |
|---|---:|---:|---:|---:|
| Cold | 716.0 ms | 841.5 ms | 2.447 / 2.891 s | 28.3 / 39.4 MB |
| Exact cache | 0.92 ms | 0.80 ms | 0.91 / 0.80 ms | 29.3 / 44.0 MB |
| Append resume | 1.10 ms | 1.35 ms | 1.91 / 2.63 ms | 29.5 / 40.0 MB |

Exact reads consumed zero bytes; append reads consumed 3,360 bytes for 24 files in both revisions. Peak footprint is process-lifetime, including cache warmup, not incremental-path allocation. The new bounded deduplication state and cache-write fields add memory and cold-parse work. Cold elapsed time increased about 18% on this tool-heavy corpus; cache paths remain millisecond-scale. These are measurements, not power or watt estimates.

`/usr/bin/time -l` process-wide counters (exact/append runs include one cold warmup; they are **not** isolated cache-path instruction counts):

| Path | Instructions before / after | Cycles before / after | Voluntary switches before / after | Involuntary switches before / after |
|---|---:|---:|---:|---:|
| Cold | 31.89B / 36.91B | 8.06B / 9.58B | 48 / 0 | 824 / 591 |
| Exact | 31.85B / 36.92B | 8.00B / 9.55B | 0 / 0 | 727 / 653 |
| Append | 31.87B / 36.94B | 8.00B / 9.49B | 0 / 0 | 928 / 688 |

Reproduce with the same harness compiled against each revision's core sources:

```sh
swiftc -O -parse-as-library -swift-version 6 \
  Sources/ModexCore/Core/*.swift Sources/ModexCore/Models/*.swift \
  Sources/ModexCore/Services/*.swift Benchmarks/CurrentCodex/main.swift -o /tmp/modex-bench
/tmp/modex-bench /tmp/modex-benchmark-corpus generate
/usr/bin/time -l /tmp/modex-bench /tmp/modex-benchmark-corpus cold
/usr/bin/time -l /tmp/modex-bench /tmp/modex-benchmark-corpus exact
/usr/bin/time -l /tmp/modex-bench /tmp/modex-benchmark-corpus append
```

Generate again before each revision's append run so it starts from identical bytes. The harness writes only its explicitly supplied synthetic corpus directory; do not point it at a real Codex home.
