# Parser Comparison

This nested SwiftPM package compares Modex's current streaming byte-scan parser with `orlandos-nl/swift-json`/`IkigaJSON` on local Codex JSONL files.

Run it in release mode. Debug-mode Swift parser timings are not meaningful.

```bash
cd Benchmarks/ParserComparison
swift run -c release ParserComparison --limit 10 --iterations 5
```

Include archived sessions for the larger-file case:

```bash
swift run -c release ParserComparison --limit 30 --include-archived --iterations 3
```

Run the full local corpus with Modex's concurrent scanner path:

```bash
swift run -c release ParserComparison --limit 100000 --include-archived --iterations 3 --only modex --concurrency 4
```

Run a reproducible macOS-native measurement matrix:

```bash
Scripts/run-macos-matrix.sh
```

The script builds the benchmark in release mode, runs each variant through `/usr/bin/time -l`, stores raw output under `Results/raw-*`, and writes a Markdown summary under `Results/`. It uses macOS process counters only: maximum resident set size, peak memory footprint, instructions retired, cycles elapsed, and context switches.

Measure one variant manually with macOS `time`:

```bash
/usr/bin/time -l .build/release/ParserComparison --limit 100000 --include-archived --iterations 1 --only modex --concurrency 4
/usr/bin/time -l .build/release/ParserComparison --limit 100000 --include-archived --iterations 1 --only ikiga-all --concurrency 4
```

Variants:

- `modex`: current Modex `CodexSessionScanner` with configurable file concurrency.
- `nio-scan`: benchmark-local SwiftNIO `ByteBuffer` line scanner with custom byte-field extraction.
- `ikiga-all`: parse every JSONL line with `JSONObject`.
- `ikiga-prefilter`: run a simple byte relevance prefilter, then parse matching lines with `JSONObject`.

## Current Full-Corpus Result

Measured on 197 local active+archived Codex JSONL files, about 1.5 GB total. Each row uses one warmup pass plus one timed pass. The `Timed scan` column comes from the benchmark's own timed pass; the macOS counters cover the whole process run, including warmup.

| Variant | Conc | Timed scan | Max RSS | Instructions | Cycles | Invol ctx switches |
|---|---:|---:|---:|---:|---:|---:|
| Modex | `1x` | `8.28s` | `287 MB` | `208.8B` | `57.2B` | `1,978` |
| Modex | `2x` | `4.30s` | `268 MB` | `208.8B` | `56.8B` | `2,943` |
| Modex | `4x` | `2.19s` | `400 MB` | `208.8B` | `56.8B` | `2,436` |
| Modex | `8x` | `1.29s` | `483 MB` | `208.8B` | `57.3B` | `3,655` |
| NIO scan | `1x` | `12.79s` | `282 MB` | `562.4B` | `86.7B` | `5,357` |
| NIO scan | `2x` | `6.48s` | `371 MB` | `562.3B` | `85.7B` | `5,276` |
| NIO scan | `4x` | `3.24s` | `338 MB` | `558.9B` | `85.2B` | `5,504` |
| NIO scan | `8x` | `1.81s` | `516 MB` | `558.9B` | `85.0B` | `3,864` |
| Ikiga | `1x` | `9.91s` | `357 MB` | `255.4B` | `67.6B` | `4,120` |
| Ikiga | `2x` | `5.20s` | `406 MB` | `257.0B` | `68.6B` | `90,483` |
| Ikiga | `4x` | `3.27s` | `505 MB` | `261.8B` | `76.0B` | `370,612` |
| Ikiga | `8x` | `2.76s` | `522 MB` | `270.8B` | `101.4B` | `738,052` |

Interpret results as an app tradeoff, not only as raw throughput. At equal file concurrency, the current Modex parser is faster, retires fewer instructions, uses fewer cycles, and creates far fewer context switches.

## SwiftNIO

The main Modex package does not use SwiftNIO. SwiftNIO appears only in this nested benchmark: directly for the `nio-scan` experiment, and transitively through `IkigaJSON`.

SwiftNIO is an evented networking and byte-buffer toolkit, not a JSON parser. The `nio-scan` experiment uses `ByteBuffer` for streaming line handling, then applies custom byte-field extraction. On the current corpus, `ByteBuffer` alone does not improve the parser: the NIO variant scales reasonably but retires many more instructions than the Modex scanner and remains slower at equal concurrency.
