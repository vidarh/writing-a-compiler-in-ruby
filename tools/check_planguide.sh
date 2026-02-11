#!/usr/bin/env bash
set -uo pipefail

# Verifies PLANGUIDE acceptance criteria: file existence, required sections,
# forbidden content, README reference, and no unintended modifications.
# Usage: bash tools/check_planguide.sh

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GUIDANCE="$ROOT/docs/improvement-planner.md"
README="$ROOT/README.md"
FAILURES=0

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILURES=$((FAILURES + 1)); }

# 1. File existence
if [ -s "$GUIDANCE" ]; then
  pass "docs/improvement-planner.md exists and is non-empty"
else
  fail "docs/improvement-planner.md does not exist or is empty"
fi

# 2. Required sections
if head -1 "$GUIDANCE" | grep -q '^# '; then
  pass "Top-level heading present"
else
  fail "No top-level heading (# ) found"
fi

if grep -qi 'do not propose' "$GUIDANCE"; then
  pass "\"Do NOT propose\" section present"
else
  fail "\"Do NOT propose\" section missing"
fi

if grep -qi 'do propose' "$GUIDANCE"; then
  pass "\"DO propose\" section present"
else
  fail "\"DO propose\" section missing"
fi

if grep -q 'run_rubyspec' "$GUIDANCE"; then
  pass "Investigation workflow references run_rubyspec"
else
  fail "No reference to run_rubyspec in guidance file"
fi

if grep -q 'make selftest' "$GUIDANCE"; then
  pass "Validation requirements reference make selftest"
else
  fail "No reference to make selftest in guidance file"
fi

# 3. Forbidden content absent
if grep -q 'investigate-spec' "$GUIDANCE"; then
  fail "Forbidden string 'investigate-spec' found in guidance file"
else
  pass "No forbidden string 'investigate-spec'"
fi

if grep -q 'validate-fix' "$GUIDANCE"; then
  fail "Forbidden string 'validate-fix' found in guidance file"
else
  pass "No forbidden string 'validate-fix'"
fi

if grep -q 'create-minimal-test' "$GUIDANCE"; then
  fail "Forbidden string 'create-minimal-test' found in guidance file"
else
  pass "No forbidden string 'create-minimal-test'"
fi

# 4. README.md reference (must be on its own line)
if grep -qx '@docs/improvement-planner.md' "$README"; then
  pass "README.md contains @docs/improvement-planner.md on its own line"
else
  fail "README.md missing bare @docs/improvement-planner.md line"
fi

# 5. No unintended modifications
CHANGED=$(cd "$ROOT" && git diff --name-only HEAD)
UNINTENDED=0

for f in $CHANGED; do
  case "$f" in
    README.md) ;;
    docs/improvement-planner.md) ;;
    docs/plans/*) ;;
    tools/check_planguide.sh) ;;
    *) ;;
  esac
done

if echo "$CHANGED" | grep -q '^CLAUDE\.md$'; then
  fail "CLAUDE.md was modified"
  UNINTENDED=1
fi

if echo "$CHANGED" | grep -q '^Makefile$'; then
  fail "Makefile was modified"
  UNINTENDED=1
fi

if echo "$CHANGED" | grep -q '^\.claude/skills/'; then
  fail "Files in .claude/skills/ were modified"
  UNINTENDED=1
fi

if echo "$CHANGED" | grep -q '^rubyspec/'; then
  fail "Files in rubyspec/ were modified"
  UNINTENDED=1
fi

if [ "$UNINTENDED" -eq 0 ]; then
  pass "No unintended file modifications"
fi

# Edge case: line count
LINES=$(wc -l < "$GUIDANCE")
if [ "$LINES" -le 120 ]; then
  pass "Guidance file is $LINES lines (under 120 limit)"
else
  fail "Guidance file is $LINES lines (exceeds 120 limit)"
fi

# Summary
echo ""
if [ "$FAILURES" -eq 0 ]; then
  echo "All checks passed."
  exit 0
else
  echo "$FAILURES check(s) failed."
  exit 1
fi
