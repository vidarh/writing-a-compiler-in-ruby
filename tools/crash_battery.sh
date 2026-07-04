#!/bin/bash
# Crash-regression battery: compile and run every repro in test/repros/battery/
# under ASLR-off (setarch -R) and report any crash (rc >= 134) or hang (rc 124).
# Part of the commit gate alongside make selftest / selftest-c.
cd "$(dirname "$0")/.." || exit 1
pass=0; fail=""
total=0
for f in test/repros/battery/*.rb; do
  t=$(basename "$f" .rb)
  total=$((total+1))
  ./compile "$f" -I. -I lib/core >/dev/null 2>&1 || { fail="$fail $t(CF)"; continue; }
  timeout 15 setarch -R "./out/$t" >/dev/null 2>&1; rc=$?
  if [ $rc -ge 134 ] || [ $rc -eq 124 ]; then fail="$fail $t(rc=$rc)"; else pass=$((pass+1)); fi
done
echo "no-crash: $pass/$total"
echo "CRASH/CF:$fail"
[ -z "$fail" ]
