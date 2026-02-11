#!/bin/bash
# GITCLEAN verification script
# Validates all acceptance criteria after plan execution.
#
# Usage:
#   bash docs/plans/GITCLEAN-commit-dirty-state-add-branch-policy/verify.sh
#   SKIP_SELFTEST=1 bash docs/plans/GITCLEAN-commit-dirty-state-add-branch-policy/verify.sh

set -e

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

pass() {
  echo "PASS: $1"
  PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
  echo "FAIL: $1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

skip() {
  echo "SKIP: $1"
  SKIP_COUNT=$((SKIP_COUNT + 1))
}

# --------------------------------------------------------------------------
# 1. Rubyspec Submodule Is Clean
# --------------------------------------------------------------------------

# 1a: Submodule not modified in parent repo
if git diff --quiet rubyspec 2>/dev/null; then
  pass "1a: rubyspec submodule not modified in parent repo"
else
  fail "1a: rubyspec submodule shows changes in parent repo"
fi

# 1b: No modified or untracked files inside submodule
submodule_status=$(git -C rubyspec status --porcelain 2>/dev/null || echo "ERROR")
if [ -z "$submodule_status" ]; then
  pass "1b: rubyspec submodule has no modified or untracked files"
else
  fail "1b: rubyspec submodule has dirty state: $submodule_status"
fi

# 1c: Submodule pointer still references 6267cc7
lstree=$(git ls-tree HEAD rubyspec 2>/dev/null)
if echo "$lstree" | grep -q "6267cc7"; then
  pass "1c: rubyspec submodule pointer references 6267cc7"
else
  fail "1c: rubyspec submodule pointer does not reference 6267cc7 (got: $lstree)"
fi

# 1d: Previously modified tracked files at upstream state
for f in core/integer/fixtures/classes.rb core/integer/shared/abs.rb spec_helper.rb; do
  diff_output=$(git -C rubyspec diff HEAD -- "$f" 2>/dev/null)
  if [ -z "$diff_output" ]; then
    pass "1d: rubyspec/$f is at upstream state"
  else
    fail "1d: rubyspec/$f has local modifications"
  fi
done

# --------------------------------------------------------------------------
# 2. Working Tree Is Clean
# --------------------------------------------------------------------------

# 2a: git status --porcelain is empty
status_output=$(git status --porcelain 2>/dev/null)
if [ -z "$status_output" ]; then
  pass "2a: working tree is clean (git status --porcelain empty)"
else
  fail "2a: working tree is not clean: $status_output"
fi

# 2b: No unstaged or staged changes
if git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null; then
  pass "2b: no unstaged or staged changes"
else
  fail "2b: unstaged or staged changes detected"
fi

# --------------------------------------------------------------------------
# 3. Thematic Commits Exist
# --------------------------------------------------------------------------

# 3a: At least 6 commits in last 10
commit_count=$(git log --oneline -10 | wc -l)
if [ "$commit_count" -ge 6 ]; then
  pass "3a: $commit_count commits in last 10 (>= 6 required)"
else
  fail "3a: only $commit_count commits in last 10 (>= 6 required)"
fi

# 3b: Commit messages cover at least 3 expected work streams
recent_msgs=$(git log --oneline -10 | tr '[:upper:]' '[:lower:]')
keyword_matches=0
echo "$recent_msgs" | grep -qi "doc" && keyword_matches=$((keyword_matches + 1))
echo "$recent_msgs" | grep -qi "peephole" && keyword_matches=$((keyword_matches + 1))
echo "$recent_msgs" | grep -qiE "plan|infrastructure" && keyword_matches=$((keyword_matches + 1))
echo "$recent_msgs" | grep -qiE "tool|spec" && keyword_matches=$((keyword_matches + 1))
echo "$recent_msgs" | grep -qiE "policy|workflow|submodule" && keyword_matches=$((keyword_matches + 1))

if [ "$keyword_matches" -ge 3 ]; then
  pass "3b: commit messages cover $keyword_matches/5 expected work streams (>= 3 required)"
else
  fail "3b: commit messages cover only $keyword_matches/5 expected work streams (>= 3 required)"
fi

# 3c: No single commit touches more than 30 files
max_files=0
while IFS= read -r line; do
  count=$(echo "$line" | grep -oE '^[0-9]+' || echo "0")
  if [ "$count" -gt "$max_files" ]; then
    max_files=$count
  fi
done < <(git log --oneline --shortstat -10 | grep "file")

if [ "$max_files" -le 30 ]; then
  pass "3c: no single commit touches more than 30 files (max: $max_files)"
else
  fail "3c: a commit touches $max_files files (> 30 limit)"
fi

# --------------------------------------------------------------------------
# 4. Deleted Docs Are Gone
# --------------------------------------------------------------------------

for f in docs/DEVELOPMENT_RULES.md docs/KERNEL_MIGRATION_PLAN.md docs/REJECTED_APPROACH_METHOD_CHAINING.md docs/RUBYSPEC_CRASH_ANALYSIS.md docs/RUBYSPEC_INTEGRATION.md; do
  label=$(basename "$f")
  if [ ! -e "$f" ]; then
    pass "4: $label does not exist (deleted)"
  else
    fail "4: $label still exists"
  fi
done

# --------------------------------------------------------------------------
# 5. Planning Infrastructure Committed
# --------------------------------------------------------------------------

# 5a: docs/plans/ exists and has files
if [ -d docs/plans ] && [ "$(ls docs/plans/ | wc -l)" -gt 0 ]; then
  pass "5a: docs/plans/ exists and contains files"
else
  fail "5a: docs/plans/ missing or empty"
fi

# 5b: docs/goals/ exists and has files
if [ -d docs/goals ] && [ "$(ls docs/goals/ | wc -l)" -gt 0 ]; then
  pass "5b: docs/goals/ exists and contains files"
else
  fail "5b: docs/goals/ missing or empty"
fi

# 5c: docs/exploration/ exists and has files
if [ -d docs/exploration ] && [ "$(ls docs/exploration/ | wc -l)" -gt 0 ]; then
  pass "5c: docs/exploration/ exists and contains files"
else
  fail "5c: docs/exploration/ missing or empty"
fi

# --------------------------------------------------------------------------
# 6. New Tools and Specs Committed
# --------------------------------------------------------------------------

# 6a: tools/asm_diff_counts.rb
if [ -f tools/asm_diff_counts.rb ] && git ls-files --error-unmatch tools/asm_diff_counts.rb >/dev/null 2>&1; then
  pass "6a: tools/asm_diff_counts.rb exists and is tracked"
else
  fail "6a: tools/asm_diff_counts.rb missing or untracked"
fi

# 6b: tools/check_planguide.sh
if [ -f tools/check_planguide.sh ] && git ls-files --error-unmatch tools/check_planguide.sh >/dev/null 2>&1; then
  pass "6b: tools/check_planguide.sh exists and is tracked"
else
  fail "6b: tools/check_planguide.sh missing or untracked"
fi

# 6c: spec/minimal_heredoc_spec.rb
if [ -f spec/minimal_heredoc_spec.rb ] && git ls-files --error-unmatch spec/minimal_heredoc_spec.rb >/dev/null 2>&1; then
  pass "6c: spec/minimal_heredoc_spec.rb exists and is tracked"
else
  fail "6c: spec/minimal_heredoc_spec.rb missing or untracked"
fi

# --------------------------------------------------------------------------
# 7. CLAUDE.md Contains Rubyspec Submodule Policy
# --------------------------------------------------------------------------

# 7a: Section heading
count_7a=$(grep -c "Rubyspec Submodule" CLAUDE.md || true)
if [ "$count_7a" -ge 1 ]; then
  pass "7a: CLAUDE.md contains 'Rubyspec Submodule' heading"
else
  fail "7a: CLAUDE.md missing 'Rubyspec Submodule' heading"
fi

# 7b: Forbids local modifications
count_7b=$(grep -ciE "never modify|never commit.*rubyspec|must not.*modify|forbid.*changes.*rubyspec" CLAUDE.md || true)
if [ "$count_7b" -ge 1 ]; then
  pass "7b: CLAUDE.md forbids local modifications to rubyspec"
else
  fail "7b: CLAUDE.md does not explicitly forbid local modifications to rubyspec"
fi

# 7c: Aspiration to pass unmodified upstream
count_7c=$(grep -ciE "unmodified.*upstream|upstream.*unmodified|pass.*unmodified" CLAUDE.md || true)
if [ "$count_7c" -ge 1 ]; then
  pass "7c: CLAUDE.md mentions aspiration to pass unmodified upstream rubyspec"
else
  fail "7c: CLAUDE.md does not mention unmodified upstream aspiration"
fi

# 7d: run_rubyspec is temporary
count_7d=$(grep -ciE "temporary|interim" CLAUDE.md || true)
if [ "$count_7d" -ge 1 ]; then
  pass "7d: CLAUDE.md mentions run_rubyspec as temporary/interim"
else
  fail "7d: CLAUDE.md does not mention run_rubyspec as temporary"
fi

# 7e: Workarounds outside submodule
count_7e=$(grep -ciE "outside.*submodule|outside.*rubyspec" CLAUDE.md || true)
if [ "$count_7e" -ge 1 ]; then
  pass "7e: CLAUDE.md states workarounds must live outside the submodule"
else
  fail "7e: CLAUDE.md does not mention workarounds outside submodule"
fi

# --------------------------------------------------------------------------
# 8. CLAUDE.md Contains Git Workflow Policy
# --------------------------------------------------------------------------

# 8a: Section heading
count_8a=$(grep -c "Git Workflow" CLAUDE.md || true)
if [ "$count_8a" -ge 1 ]; then
  pass "8a: CLAUDE.md contains 'Git Workflow' heading"
else
  fail "8a: CLAUDE.md missing 'Git Workflow' heading"
fi

# 8b: Requires feature branches
count_8b=$(grep -ci "feature branch" CLAUDE.md || true)
if [ "$count_8b" -ge 1 ]; then
  pass "8b: CLAUDE.md requires feature branches"
else
  fail "8b: CLAUDE.md does not mention feature branches"
fi

# 8c: Commit before starting new tasks
count_8c=$(grep -ciE "commit.*before|before.*start|clean.*before" CLAUDE.md || true)
if [ "$count_8c" -ge 1 ]; then
  pass "8c: CLAUDE.md requires committing before starting new tasks"
else
  fail "8c: CLAUDE.md does not mention committing before new tasks"
fi

# 8d: Clean working tree
count_8d=$(grep -ciE "clean.*working.*tree|working.*tree.*clean|clean.*before.*new" CLAUDE.md || true)
if [ "$count_8d" -ge 1 ]; then
  pass "8d: CLAUDE.md requires clean working tree"
else
  fail "8d: CLAUDE.md does not mention clean working tree"
fi

# --------------------------------------------------------------------------
# 9. Compiler Still Works
# --------------------------------------------------------------------------

if [ "${SKIP_SELFTEST:-0}" = "1" ]; then
  skip "9a: make selftest (SKIP_SELFTEST=1)"
  skip "9b: make selftest-c (SKIP_SELFTEST=1)"
else
  if make selftest >/dev/null 2>&1; then
    pass "9a: make selftest passes"
  else
    fail "9a: make selftest failed"
  fi

  if make selftest-c >/dev/null 2>&1; then
    pass "9b: make selftest-c passes"
  else
    fail "9b: make selftest-c failed"
  fi
fi

# --------------------------------------------------------------------------
# 10. No Rubyspec Junk Files
# --------------------------------------------------------------------------

for f in rubyspec/compiler_stubs.rb rubyspec/simple_tests rubyspec/test_bignum_basic.rb rubyspec/temp_bignum_plus_test.rb; do
  label=$(basename "$f")
  if [ ! -e "$f" ]; then
    pass "10: rubyspec/$label does not exist (cleaned)"
  else
    fail "10: rubyspec/$label still exists"
  fi
done

# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------

echo ""
echo "========================================="
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed, $SKIP_COUNT skipped"
echo "========================================="

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi

exit 0
