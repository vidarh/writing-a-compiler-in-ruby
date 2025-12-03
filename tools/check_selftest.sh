#!/usr/bin/env bash
set -euo pipefail

# Regenerates selftest.s twice and reports any differences using tools/compare_asm.rb
# Usage: tools/check_selftest.sh

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT1="$(mktemp)"
OUT2="$(mktemp)"
cleanup() { rm -f "$OUT1" "$OUT2"; }
trap cleanup EXIT

cd "$ROOT"

ruby -I. ./driver.rb test/selftest.rb -I. -g > "$OUT1"
ruby -I. ./driver.rb test/selftest.rb -I. -g > "$OUT2"

ruby tools/compare_asm.rb "$OUT1" "$OUT2"
