#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BENCHMARK_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
RESULTS_DIR="${RESULTS_DIR:-$BENCHMARK_DIR/Results}"
LIMIT="${LIMIT:-100000}"
ITERATIONS="${ITERATIONS:-1}"
CONCURRENCIES="${CONCURRENCIES:-1 2 4 8}"
VARIANTS="${VARIANTS:-modex nio-scan ikiga-all}"
INCLUDE_ARCHIVED="${INCLUDE_ARCHIVED:-1}"

mkdir -p "$RESULTS_DIR"
cd "$BENCHMARK_DIR"

swift build -c release --product ParserComparison >/dev/null

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
summary="$RESULTS_DIR/parser-comparison-$timestamp.md"
raw_dir="$RESULTS_DIR/raw-$timestamp"
mkdir -p "$raw_dir"

{
  echo "# Parser Comparison $timestamp"
  echo
  echo "- Limit: \`$LIMIT\`"
  echo "- Iterations after warmup: \`$ITERATIONS\`"
  echo "- Include archived: \`$INCLUDE_ARCHIVED\`"
  echo "- Concurrencies: \`$CONCURRENCIES\`"
  echo "- Variants: \`$VARIANTS\`"
  echo
  echo "| Variant | Concurrency | Timed scan | Max RSS | Peak footprint | Instructions | Cycles | Vol ctx | Invol ctx |"
  echo "|---|---:|---:|---:|---:|---:|---:|---:|---:|"
} >"$summary"

for concurrency in $CONCURRENCIES; do
  for variant in $VARIANTS; do
    name="${variant}-${concurrency}x"
    stdout_file="$raw_dir/$name.out"
    time_file="$raw_dir/$name.time"
    args=(
      ".build/release/ParserComparison"
      "--limit" "$LIMIT"
      "--iterations" "$ITERATIONS"
      "--only" "$variant"
      "--concurrency" "$concurrency"
    )
    if [[ "$INCLUDE_ARCHIVED" != "0" ]]; then
      args+=("--include-archived")
    fi

    /usr/bin/time -l "${args[@]}" >"$stdout_file" 2>"$time_file"

    timed_scan="$(
      awk '/^(modex-streaming-byte-scan|nio-bytebuffer-scan|ikiga-jsonobject-all-lines|ikiga-jsonobject-prefilter)/ { print $3; exit }' "$stdout_file"
    )"
    max_rss="$(
      awk '/maximum resident set size/ { printf "%.0f MB", $1 / 1024 / 1024; exit }' "$time_file"
    )"
    peak_footprint="$(
      awk '/peak memory footprint/ { printf "%.0f MB", $1 / 1024 / 1024; exit }' "$time_file"
    )"
    instructions="$(
      awk '/instructions retired/ { printf "%.1fB", $1 / 1000000000; exit }' "$time_file"
    )"
    cycles="$(
      awk '/cycles elapsed/ { printf "%.1fB", $1 / 1000000000; exit }' "$time_file"
    )"
    voluntary="$(
      awk '/voluntary context switches/ { print $1; exit }' "$time_file"
    )"
    involuntary="$(
      awk '/involuntary context switches/ { print $1; exit }' "$time_file"
    )"

    echo "| \`$variant\` | $concurrency | $timed_scan | $max_rss | $peak_footprint | $instructions | $cycles | $voluntary | $involuntary |" >>"$summary"
  done
done

echo "$summary"
