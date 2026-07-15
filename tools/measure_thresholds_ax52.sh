#!/bin/bash
# Sweep INLINE_MAX_NODES thresholds on ax52 and measure ratio.
# Run from repo root after syncing.
set -euo pipefail

RUNS="${RUNS:-3}"
THRESHOLDS="${THRESHOLDS:-10 20 30 40 60 100 200}"
LOG="${LOG:-/tmp/threshold_sweep.log}"
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

echo "== threshold sweep: selftest and driver ==" | tee -a "$LOG"

for workload in test/selftest.rb driver.rb; do
  for thresh in $THRESHOLDS; do
    export INLINE_MAX_NODES="$thresh"
    echo "-- $workload INLINE_MAX_NODES=$thresh --" | tee -a "$LOG"
    for i in $(seq 1 "$RUNS"); do
      run_time "${workload}:t${thresh}:compile:$i" ./compile "$workload" -I.
    done
    for i in $(seq 1 "$RUNS"); do
      run_time "${workload}:t${thresh}:compile2:$i" ./compile2 "$workload" -I.
    done
  done
done

echo "== summary ==" | tee -a "$LOG"
awk '
  { split($1, a, ":"); workload=a[1]; thresh=a[2]; kind=a[3]; n=a[4]; v=$2 }
  { sum[workload,thresh,kind] += v; cnt[workload,thresh,kind] += 1 }
  END {
    for (comb in sum) {
      split(comb, b, SUBSEP)
      avg = sum[comb] / cnt[comb]
      printf "%s %s %s avg=%.3fs\n", b[1], b[2], b[3], avg
    }
  }
' "$LOG"
