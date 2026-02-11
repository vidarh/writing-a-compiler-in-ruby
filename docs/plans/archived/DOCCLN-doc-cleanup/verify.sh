#!/bin/bash
# DOCCLN verification script
# Validates all acceptance criteria for the documentation cleanup plan.
# Exits 0 on success, non-zero on first failure.

set -e

PASS=0
FAIL=0

pass() {
  echo "PASS: $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "FAIL: $1"
  FAIL=$((FAIL + 1))
}

# --- 1. File Deletion (6 scenarios) ---

for f in \
  docs/DEVELOPMENT_RULES.md \
  docs/RUBYSPEC_INTEGRATION.md \
  docs/RUBYSPEC_CRASH_ANALYSIS.md \
  docs/REJECTED_APPROACH_METHOD_CHAINING.md \
  docs/KERNEL_MIGRATION_PLAN.md \
  docs/INVESTIGATION_POSTFIX_IF_BUG.md
do
  if [ ! -e "$f" ]; then
    pass "1. Deleted: $f"
  else
    fail "1. Still exists: $f"
  fi
done

# --- 2. No Broken Cross-References ---

# 2a: control_flow_as_expressions.md must not have active "See REJECTED_APPROACH_METHOD_CHAINING.md" directive
count=$(grep -c "See REJECTED_APPROACH_METHOD_CHAINING.md" docs/control_flow_as_expressions.md || true)
if [ "$count" -eq 0 ]; then
  pass "2a. No active 'See REJECTED_APPROACH...' reference in control_flow_as_expressions.md"
else
  fail "2a. Found $count active 'See REJECTED_APPROACH...' references in control_flow_as_expressions.md"
fi

# 2b: bignums.md must not reference non-existent investigation files
count=$(grep -c "FIXNUM_CLASS_METHOD_INVESTIGATION\|FIXNUM_TO_INTEGER_MIGRATION" docs/bignums.md || true)
if [ "$count" -eq 0 ]; then
  pass "2b. No stale file references in bignums.md"
else
  fail "2b. Found $count stale file references in bignums.md"
fi

# --- 3. KNOWN_ISSUES.md — No FIXED Items in Active Issues ---

# Extract Active Issues section (between ## Active Issues and next ## heading)
active_section=$(sed -n '/^## Active Issues/,/^## [^A]/p' docs/KNOWN_ISSUES.md)

# 3a: No FIXED in Active Issues section
count=$(echo "$active_section" | grep -ci "FIXED" || true)
if [ "$count" -eq 0 ]; then
  pass "3a. No FIXED items in Active Issues section"
else
  fail "3a. Found $count occurrences of FIXED in Active Issues section"
fi

# 3b: super() and Classes in Lambdas removed from Active Issues
count_super=$(echo "$active_section" | grep -c "super() Uses Wrong Superclass" || true)
count_lambda=$(echo "$active_section" | grep -c "Classes in Lambdas" || true)
if [ "$count_super" -eq 0 ] && [ "$count_lambda" -eq 0 ]; then
  pass "3b. 'super() Uses Wrong Superclass' and 'Classes in Lambdas' not in Active Issues"
else
  fail "3b. Found removed issues still in Active Issues (super=$count_super, lambda=$count_lambda)"
fi

# 3c: Sequential numbering: ### 1., ### 2., ### 3. exist; ### 4. and ### 5. do not
has_1=$(echo "$active_section" | grep -c "^### 1\." || true)
has_2=$(echo "$active_section" | grep -c "^### 2\." || true)
has_3=$(echo "$active_section" | grep -c "^### 3\." || true)
has_4=$(echo "$active_section" | grep -c "^### 4\." || true)
has_5=$(echo "$active_section" | grep -c "^### 5\." || true)
if [ "$has_1" -ge 1 ] && [ "$has_2" -ge 1 ] && [ "$has_3" -ge 1 ] && [ "$has_4" -eq 0 ] && [ "$has_5" -eq 0 ]; then
  pass "3c. Active issues numbered sequentially 1-3 with no gaps"
else
  fail "3c. Active issue numbering wrong (1=$has_1, 2=$has_2, 3=$has_3, 4=$has_4, 5=$has_5)"
fi

# --- 4. KNOWN_ISSUES.md — Spec Counts Match rubyspec_language.txt ---

# Extract expected values from rubyspec_language.txt (strip ANSI codes)
rubyspec_clean=$(sed 's/\x1b\[[0-9;]*m//g' docs/rubyspec_language.txt)
expected_passed=$(echo "$rubyspec_clean" | grep "^  Passed:" | head -1 | grep -oE '[0-9]+')
expected_failed=$(echo "$rubyspec_clean" | grep "^  Failed:" | head -1 | grep -oE '[0-9]+')
expected_crashed=$(echo "$rubyspec_clean" | grep "^  Crashed" | head -1 | grep -oE '[0-9]+')
expected_total_tests=$(echo "$rubyspec_clean" | grep "^  Total tests:" | grep -oE '[0-9]+')
expected_tests_passed=$(echo "$rubyspec_clean" | grep "^  Passed:" | tail -1 | grep -oE '[0-9]+')
expected_pass_rate=$(echo "$rubyspec_clean" | grep "Pass rate:" | grep -oE '[0-9]+%')

ki_content=$(cat docs/KNOWN_ISSUES.md)

# 4a: Passed file count
if echo "$ki_content" | grep -qi "Passed.*$expected_passed"; then
  pass "4a. KNOWN_ISSUES.md contains Passed: $expected_passed"
else
  fail "4a. KNOWN_ISSUES.md missing Passed: $expected_passed"
fi

# 4b: Failed and Crashed file counts
if echo "$ki_content" | grep -q "$expected_failed" && echo "$ki_content" | grep -q "$expected_crashed"; then
  pass "4b. KNOWN_ISSUES.md contains failed=$expected_failed and crashed=$expected_crashed"
else
  fail "4b. KNOWN_ISSUES.md missing failed=$expected_failed or crashed=$expected_crashed"
fi

# 4c: Individual test case stats
if echo "$ki_content" | grep -q "$expected_total_tests" && echo "$ki_content" | grep -q "$expected_tests_passed" && echo "$ki_content" | grep -q "$expected_pass_rate"; then
  pass "4c. KNOWN_ISSUES.md contains individual test stats ($expected_total_tests total, $expected_tests_passed passed, $expected_pass_rate)"
else
  fail "4c. KNOWN_ISSUES.md missing individual test stats ($expected_total_tests, $expected_tests_passed, $expected_pass_rate)"
fi

# --- 5. TODO.md — No FIXED Active Items ---

todo_content=$(cat docs/TODO.md)

# 5a: No "Classes in Lambdas - FIXED" section
count=$(grep -c "Classes in Lambdas.*FIXED" docs/TODO.md || true)
if [ "$count" -eq 0 ]; then
  pass "5a. No 'Classes in Lambdas - FIXED' in TODO.md"
else
  fail "5a. Found $count 'Classes in Lambdas - FIXED' in TODO.md"
fi

# 5b: No section heading with FIXED
count=$(grep -c "^### .*FIXED" docs/TODO.md || true)
if [ "$count" -eq 0 ]; then
  pass "5b. No section headings with FIXED in TODO.md"
else
  fail "5b. Found $count section headings with FIXED in TODO.md"
fi

# --- 6. TODO.md — Spec Counts Match rubyspec_language.txt ---

# 6a: Failed and crashed file counts
if echo "$todo_content" | grep -q "$expected_failed" && echo "$todo_content" | grep -q "$expected_crashed"; then
  pass "6a. TODO.md contains failed=$expected_failed and crashed=$expected_crashed"
else
  fail "6a. TODO.md missing failed=$expected_failed or crashed=$expected_crashed"
fi

# 6b: Individual test stats
if echo "$todo_content" | grep -q "$expected_total_tests" && echo "$todo_content" | grep -q "$expected_tests_passed" && echo "$todo_content" | grep -q "$expected_pass_rate"; then
  pass "6b. TODO.md contains individual test stats ($expected_total_tests, $expected_tests_passed, $expected_pass_rate)"
else
  fail "6b. TODO.md missing individual test stats ($expected_total_tests, $expected_tests_passed, $expected_pass_rate)"
fi

# --- 7. bignums.md — Size and Content ---

# 7a: Under 250 lines
line_count=$(wc -l < docs/bignums.md)
if [ "$line_count" -lt 250 ]; then
  pass "7a. bignums.md is $line_count lines (under 250)"
else
  fail "7a. bignums.md is $line_count lines (should be under 250)"
fi

# 7b: Required section headings
bignums_lower=$(tr '[:upper:]' '[:lower:]' < docs/bignums.md)

check_section() {
  local label="$1"
  local pattern="$2"
  if echo "$bignums_lower" | grep -qi "$pattern"; then
    pass "7b. bignums.md contains section: $label"
  else
    fail "7b. bignums.md missing section: $label"
  fi
}

check_section "status" "status"
check_section "memory layout" "memory layout\|representation"
check_section "phase" "phase"
check_section "limitation/future" "limitation\|future"
check_section "design/decision" "design\|decision"
check_section "method/api" "method\|api"

# 7c: No "Commit" keyword (case-sensitive)
count=$(grep -c "Commit" docs/bignums.md || true)
if [ "$count" -eq 0 ]; then
  pass "7c. No 'Commit' keyword in bignums.md"
else
  fail "7c. Found $count 'Commit' references in bignums.md"
fi

# 7d: No stale file references (already checked in 2b, but explicit)
count=$(grep -c "FIXNUM_CLASS_METHOD_INVESTIGATION\|FIXNUM_TO_INTEGER_MIGRATION" docs/bignums.md || true)
if [ "$count" -eq 0 ]; then
  pass "7d. No stale file references in bignums.md"
else
  fail "7d. Found $count stale file references in bignums.md"
fi

# --- 8. Preserved Files Not Damaged ---

for f in \
  docs/ARCHITECTURE.md \
  docs/DEBUGGING_GUIDE.md \
  docs/TODO.md \
  docs/KNOWN_ISSUES.md \
  docs/bignums.md \
  docs/control_flow_as_expressions.md \
  docs/rubyspec_language.txt
do
  if [ -f "$f" ]; then
    pass "8. Preserved: $f"
  else
    fail "8. Missing preserved file: $f"
  fi
done

# --- Summary ---

echo ""
echo "================================"
echo "Results: $PASS passed, $FAIL failed"
echo "================================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

exit 0
