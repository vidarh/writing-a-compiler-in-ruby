#!/usr/bin/env bash
# SLOWRUN verification script — checks acceptance criteria for the plan.
# Invocation: bash docs/plans/SLOWRUN-add-slow-target-guidance/verify.sh
# Exit 0 = all pass, non-zero = at least one failure.

set -euo pipefail

PLANNER="docs/improvement-planner.md"
CLAUDE="CLAUDE.md"
PASS=0
FAIL=0

check() {
  local description="$1"
  local result="$2"  # 0 = pass, non-zero = fail
  if [ "$result" -eq 0 ]; then
    echo "PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $description"
    FAIL=$((FAIL + 1))
  fi
}

# ---------------------------------------------------------------------------
# Checks for docs/improvement-planner.md
# ---------------------------------------------------------------------------

# 1. Slow-targets section exists (H2 heading containing "Slow Targets")
grep -qi '^## .*Slow Targets' "$PLANNER" 2>/dev/null
check "Slow-targets section exists in improvement-planner.md" $?

# 2. Targets listed as slow / re-run only for validation
#    Must contain "make rubyspec" AND language about only re-running for validation.
has_make_rubyspec=1
has_only_rerun=1
grep -q 'make rubyspec' "$PLANNER" 2>/dev/null && has_make_rubyspec=0
grep -qiE '(only.*re-?run|only.*run.*validat|re-?run.*only.*validat)' "$PLANNER" 2>/dev/null && has_only_rerun=0
if [ "$has_make_rubyspec" -eq 0 ] && [ "$has_only_rerun" -eq 0 ]; then
  check "Targets described as slow with re-run-only-for-validation guidance" 0
else
  check "Targets described as slow with re-run-only-for-validation guidance" 1
fi

# 3. Read-the-file guidance — at least one results filename referenced
found_file=1
for f in rubyspec_language.txt rubyspec_integer.txt rubyspec_regexp.txt; do
  grep -q "$f" "$PLANNER" 2>/dev/null && found_file=0 && break
done
check "Read-the-file guidance references results files in improvement-planner.md" $found_file

# 4. Auto-write / no-manual-pipe warning — mentions tee or "automatically write"
has_autowrite=1
grep -qi 'tee' "$PLANNER" 2>/dev/null && has_autowrite=0
if [ "$has_autowrite" -ne 0 ]; then
  grep -qiE 'automatically writes?' "$PLANNER" 2>/dev/null && has_autowrite=0
fi
check "Auto-write/tee guidance found in improvement-planner.md" $has_autowrite

# ---------------------------------------------------------------------------
# Checks for CLAUDE.md
# ---------------------------------------------------------------------------

# Extract the Testing subsection (between ### Testing and next ### or ##)
testing_section=$(sed -n '/^### Testing$/,/^##/p' "$CLAUDE" | head -n -1)

# 5. Slow-target note exists in Testing subsection
echo "$testing_section" | grep -qi 'slow'
check "Slow-target note exists in CLAUDE.md Testing subsection" $?

# 6. Auto-write-to-file note in CLAUDE.md Testing subsection
has_autowrite_claude=1
echo "$testing_section" | grep -qi 'tee' && has_autowrite_claude=0
if [ "$has_autowrite_claude" -ne 0 ]; then
  echo "$testing_section" | grep -qiE 'rubyspec_.*\.txt' && has_autowrite_claude=0
fi
check "Auto-write/results-file note in CLAUDE.md Testing subsection" $has_autowrite_claude

# ---------------------------------------------------------------------------
# Edge-case checks
# ---------------------------------------------------------------------------

# 7. No reference to rubyspec_language_new.txt in improvement-planner.md
#    (This should NOT be present — so grep finding it is a failure)
if grep -q 'rubyspec_language_new.txt' "$PLANNER" 2>/dev/null; then
  check "No reference to rubyspec_language_new.txt in improvement-planner.md" 1
else
  check "No reference to rubyspec_language_new.txt in improvement-planner.md" 0
fi

# 8. make spec not listed as slow in the Slow Targets section
#    Extract the slow targets section from improvement-planner.md
slow_section=$(sed -n '/^## .*Slow Targets/,/^## /p' "$PLANNER" | head -n -1)
if echo "$slow_section" | grep -qiE '`make spec`.*slow|slow.*`make spec`'; then
  check "make spec not listed as slow target" 1
else
  check "make spec not listed as slow target" 0
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

TOTAL=$((PASS + FAIL))
echo ""
echo "Results: $PASS/$TOTAL passed"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
