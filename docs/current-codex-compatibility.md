# Current Codex compatibility — 0.1.9

## Account analytics readability — 0.1.9 (build 14)

The Tokens view now separates lifetime tokens, the displayed-days subtotal, and peak daily tokens into three aligned metrics with explicit localized million/billion units. Exact summary counts are available on hover and to accessibility. The daily strip names its entry count and date range; it contains the seven latest reported entries, not an inferred calendar week. Missing dates are not filled with zeros. The secondary statistics align with the summary columns, and longest-turn duration uses localized hours/minutes/seconds.

The reference screenshot's seven entries total **183,644,186**, below the reported lifetime **25,253,809,535**. A regression test covers that exact case, sparse dates, selection/order, missing versus zero totals, and overflow. No request, timer, scanner behavior, dependency, or persisted format changed. All 62 tests, build, one-shot reporting, optimized packaging, localization lint/key/placeholder checks, and whitespace checks pass.

Packaged 0.1.9 screenshots were inspected in System light and dark: the three summary columns, exact daily strip, date-range explanation, and expanded duration/streak statistics are readable without clipping or overlap. The collapsed layout was also checked in System light. Accessibility exposes exact summary totals. macOS Light appearance and the expanded statistics were restored after verification. The user confirmed that the Black theme is fine, completing theme acceptance; no agent-captured Black screenshot is claimed for 0.1.9.

## Acceptance completion — 0.1.8 (build 13)

The follow-up audit found and repaired the remaining implementation gaps:

| Issue | Completion evidence |
|---|---|
| #3 — account limits | Shared account model; localized CLI account report in all five languages; explicit blocked/unknown states; named quotas, workspace restriction reasons, spend controls, and read-only reset details. Unknown reason enums use generic localized copy. Promotional upsell payloads are intentionally not rendered. |
| #4 — account analytics | Shared typed usage adapter and 15-minute coordinator TTL; lifetime/peak plus longest turn and both streak statistics, with the latter in a secondary disclosure. CLI includes all five statistics and real dated buckets. Nulls remain unavailable; failed refreshes retain the original dated snapshot and show stale status. Per-thread estimates are optional and not requested. |
| #5 — modern rollouts | Completed `commandExecution`, `collabToolCall`, and `dynamicToolCall` records now supplement the existing modern/legacy classifier. Mixed command completion/failure records deduplicate by ID. Release benchmark below. |
| #6 — shared transport | Explicit disconnected/connecting/ready/limited/failed lifecycle, separate attempt/reconnect/process counters, bounded framing and request routing, demand-only backoff, shutdown with in-flight requests, process-exit and reconnect coverage. Account changes also invalidate the UI model catalog. Stderr is discarded rather than retaining potentially sensitive content. |
| #7 — model upgrades | Catalog display names, bounded plain-text migration help, explicit selection and target defaults. Saved Spark is no longer treated as a first-run fallback. Unchanged selections preserve receipts; actual model/effort/tier changes invalidate the matching identity. |
| #8 — thread metadata | Local-first enrichment, structured source/parent fields, server model/effort only when local observations are absent, per-thread notification freshness, disconnect invalidation, partial-page retention, and newer notifications preserved across pagination. Runtime scope remains limited to the connected server, as described below. |

The user's later lean-visualization requirement refines #4's initial chart proposal: exact dated daily values replace a graph; unrelated decorative graphs remain removed. No new dependency, AppKit bridge, account mutation, or background daemon is introduced.

The additive `intelligenceModelSelectionVersion` preference records unresolved first-run defaults (0) versus resolved/saved choices (1). Startup migration `preserve-saved-model-selection`, introduced at the fixed version **0.1.8**, preserves pre-existing model preferences without switching models. Old-format fixtures verify data preservation and idempotent reopening. History/cache formats are unchanged.

Automated verification: 59 tests pass, including all-locale account report coverage, old-setting migration, explicit-model/receipt behavior, all runtime states, notification identity/disconnect handling, partial pagination and status/name races, completed commands, process exit/reconnect, and shutdown with an outstanding request. Build, localization lint, cross-locale key order/placeholder checks, one-shot reporting, optimized packaging, and whitespace checks pass. The only long identical localized value is an intentional protocol-field formula.

Final packaged 0.1.8 visual verification completed on 2026-09-25. Actual screenshots were inspected for the account details in System light, the dashboard and new connection/attempt/reconnect diagnostics in System light and Black, and the expanded account statistics in System light and dark. The statistics disclosure, exact dated buckets, and account/local-total separation remain readable without overlap; the connection diagnostics fit their compact rows. The selected model had no upgrade notice, so that conditional workflow is covered by automated tests rather than a live upgrade screenshot. Screenshots remain in the verification task, not the public repository, because they contain private thread/account metadata. The original Modex System theme and macOS Light appearance were restored. Together with the checks above, this completes the acceptance verification for #3–#8 within the documented protocol boundaries.

### 0.1.7 → 0.1.8 scanner comparison

Same generated 24-file / 117,210,446-byte corpus, four parsers, optimized builds, sequential runs with no concurrent build. Values are a single paired run, not a statistical power measurement.

| Path | Before / after wall time | Before / after scan CPU | Before / after lifetime peak footprint |
|---|---:|---:|---:|
| Cold | 836.86 / 837.46 ms | 2.883 / 2.866 s | 43.8 / 41.7 MB |
| Exact cache | 0.817 / 0.888 ms | 0.815 / 0.885 ms | 41.5 / 41.1 MB |
| Append | 1.623 / 1.569 ms | 2.856 / 2.871 ms | 40.7 / 44.3 MB |

Exact-cache reads were zero bytes; append reads were 3,360 bytes in both builds. Peak memory includes warmup. Cold latency differs by 0.07%; tiny cached timings and footprint differences are subject to run-to-run variation.

| Path | Instructions before / after | Cycles before / after | Voluntary switches before / after | Involuntary switches before / after |
|---|---:|---:|---:|---:|
| Cold | 36.928B / 36.957B | 9.560B / 9.495B | 0 / 0 | 675 / 620 |
| Exact | 36.934B / 36.965B | 9.477B / 9.532B | 0 / 0 | 682 / 690 |
| Append | 36.942B / 36.979B | 9.484B / 9.475B | 0 / 0 | 685 / 624 |

These `/usr/bin/time -l` counters cover the whole benchmark process, including the cold warmup for exact/append runs. No claim about watts or whole-app energy is made.

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
- Visible analytics are lifetime tokens, peak daily tokens, and exact dated daily buckets, separate from local totals. Longest-turn and streak statistics live in a secondary disclosure. Decorative sparklines, speculative cost estimates, and redundant scan-health/dashboard history cards are omitted. Optional per-thread billing estimates are not requested.
- Model upgrades are user-selected, require an advertised target, and reset effort/speed through the existing supported-default path. Existing connection receipts consequently invalidate through their configuration identity. A missing explicit model stays visible rather than silently migrating.
- Parser deduplication retains the most recent 2,048 operation IDs and category bits per file; pending command/patch results are capped at 256 each. Duplicate lifecycle records outside that bounded window cannot be guaranteed to deduplicate. State is carried in append checkpoints, never persisted as raw logs.
- Valid legacy token counts remain authoritative. Usage-record-only logs are supported, null token-count notifications do not suppress fallback, and matching usage records enrich cache-write tokens without doubling totals. Unknown context stays unknown.

## Verification

The test suite includes old-schema history reopening, scanner priority/concurrency/cache behavior, current and mixed rollout activity, usage fallback, canonical index fields, sparse account merges, null/ordered analytics, model retirement metadata, runtime staleness rules, protocol initialization/concurrency/notifications, pagination/TTL, cancellation, malformed/oversized messages, executable replacement, backoff, and account startup announcements.

The initial live installed CLI smoke check decoded account availability, 166 reported daily buckets, and 112 paginated thread summaries without a reconnect. A 3 MB valid-response regression test covers pipe backpressure independently of the oversized-message rejection test. As of 0.1.8, CLI account reports use localized terminology rather than raw protocol field labels, retaining authoritative permission and unavailable values.

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
