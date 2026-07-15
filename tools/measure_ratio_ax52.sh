#!/bin/bash
# Measure MRI vs self-hosted compile-time ratio on ax52.
# Run from repo root after syncing.
set -euo pipefail

RUNS="${RUNS:-3}"
LOG="${LOG:-/tmp/ratio_measure.log}"
: > "$LOG"

run_time() {
  local label="$1"; shift
  local start end elapsed
  start=$(date +%s.%N)
  "$@" >/dev/null 2>&1 || { echo "FAILED: $label"; return 1; }
  end=$(date +%s.%N)
  elapsed=$(awk "BEGIN{print $end - $start}")
  echo "$label $elapsed" | tee -a "$LOG"
}

echo "== building out/driver ==" | tee -a "$LOG"
make compiler

echo "== workloads: selftest, driver ==" | tee -a "$LOG"

for workload in test/selftest.rb driver.rb; do
  echo "-- $workload --" | tee -a "$LOG"
  for i in $(seq 1 "$RUNS"); do
    run_time "${workload}:compile:$i" ./compile "$workload" -I.
  done
  for i in $(seq 1 "$RUNS"); do
    run_time "${workload}:compile2:$i" ./compile2 "$workload" -I.
  done
done

echo "== summary ==" | tee -a "$LOG"
awk '
  { split($1, a, ":"); workload=a[1]; mode=a[2]; kind=a[3]; n=a[4]; v=$2 }
  { sum[workload,mode,kind] += v; cnt[workload,mode,kind] += 1 }
  END {
    for (comb in sum) {
      split(comb, b, SUBSEP)
      avg = sum[comb] / cnt[comb]
      printf "%s:%s:%s avg=%.3fs\n", b[1], b[2], b[3], avg
    }
  }
' "$LOG"
