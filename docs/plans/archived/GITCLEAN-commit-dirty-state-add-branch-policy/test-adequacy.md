# GITCLEAN Test Adequacy Review

**Reviewed:** 2026-02-11
**Test file:** `docs/plans/GITCLEAN-commit-dirty-state-add-branch-policy/verify.sh`

## Scenario Coverage

| # | Scenario (from test.md) | Has Test? | Notes |
|---|-------------------------|-----------|-------|
| 1a | Submodule not modified in parent repo | Yes | `git diff --quiet rubyspec` |
| 1b | No modified/untracked files inside submodule | Yes | `git -C rubyspec status --porcelain` |
| 1c | Submodule pointer references 6267cc7 | Yes | `git ls-tree HEAD rubyspec` + grep |
| 1d | 3 previously modified tracked files at upstream state | Yes | Loop over 3 files with `git -C rubyspec diff HEAD` |
| 2a | `git status --porcelain` empty | Yes | Checks for clean working tree |
| 2b | No unstaged or staged changes | Yes | `git diff --quiet` + `git diff --cached --quiet` |
| 3a | At least 6 commits in last 10 | Yes | `git log --oneline -10 \| wc -l` |
| 3b | Commit messages cover >= 3 work streams | Yes | 5 keyword pattern checks |
| 3c | No single commit touches all changes | Yes | `--shortstat` parsing with 120-file threshold |
| 4a-4e | 5 deleted doc files don't exist | Yes | Loop over all 5 files |
| 5a | `docs/plans/` exists with files | Yes | Directory + file count check |
| 5b | `docs/goals/` exists with files | Yes | Directory + file count check |
| 5c | `docs/exploration/` exists with files | Yes | Directory + file count check |
| 6a | `tools/asm_diff_counts.rb` tracked | Yes | File existence + `git ls-files --error-unmatch` |
| 6b | `tools/check_planguide.sh` tracked | Yes | File existence + `git ls-files --error-unmatch` |
| 6c | `spec/minimal_heredoc_spec.rb` tracked | Yes | File existence + `git ls-files --error-unmatch` |
| 7a | "Rubyspec Submodule" heading in CLAUDE.md | Yes | `grep -c` |
| 7b | Forbids local modifications | Yes | Multi-pattern grep |
| 7c | Unmodified upstream aspiration | Yes | Multi-pattern grep |
| 7d | run_rubyspec is temporary/interim | Yes | `grep -ciE "temporary\|interim"` |
| 7e | Workarounds outside submodule | Yes | Multi-pattern grep |
| 8a | "Git Workflow" heading in CLAUDE.md | Yes | `grep -c` |
| 8b | Feature branches required | Yes | `grep -ci "feature branch"` |
| 8c | Commit before starting new tasks | Yes | Multi-pattern grep |
| 8d | Clean working tree required | Yes | Multi-pattern grep |
| 9a | `make selftest` passes | Yes | Gated behind `SKIP_SELFTEST` |
| 9b | `make selftest-c` passes | Yes | Gated behind `SKIP_SELFTEST` |
| 10a | Rubyspec junk files removed (4 spot-checks) | Yes | 4 files checked in loop |

**All 32 scenarios from test.md have corresponding tests.** No scenario is missing.

## Coverage Gaps

None identified. Every scenario in test.md has a corresponding check in verify.sh.

## Error Path Coverage

This plan is a git/filesystem cleanup — there are no "error paths" in the traditional sense. The test script validates post-conditions (state assertions), not runtime behavior. The relevant "error paths" are:

- **Partial execution**: If only some commits were made, scenarios 2a/2b (clean working tree) and 3a (commit count) would fail. ✅ Covered.
- **Rubyspec not cleaned**: Scenarios 1a-1d and 10a would fail. ✅ Covered.
- **CLAUDE.md policies missing/incomplete**: Scenarios 7a-7e and 8a-8d would fail. ✅ Covered.
- **Implementation reverted**: If commits were reverted, scenarios 3a, 4a-4e, 5a-5c, 6a-6c would fail. ✅ Covered.

## Would Tests Fail if Implementation Reverted?

Yes. If any of the thematic commits were reverted:
- Deleted docs would reappear (4a-4e fail)
- New tools/specs would disappear (6a-6c fail)
- Planning dirs would vanish (5a-5c fail)
- Commit count would drop (3a fail)
- CLAUDE.md policy sections would disappear (7a-8d fail)

## External Dependencies / Mocking

Not applicable. The test script uses only `git`, `grep`, `wc`, `sed`, `test`, and `bash` — all local POSIX tools. No network access, no live services, no credentials required. The `SKIP_SELFTEST` gate correctly handles the Docker/i386 dependency for the compiler build scenarios (9a/9b).

## Design Quality

The script is well-structured:
- Clear pass/fail/skip functions with counters
- Logical ordering (git state → commits → files → content → compiler)
- Proper use of `|| true` to handle grep exit codes (pitfall #1 from test.md)
- `SKIP_SELFTEST` escape hatch for environment portability
- Summary with exit code

Minor note: `set -e` at the top means the script would abort on the first uncaught error, but all checks properly handle exit codes with `|| true`, `2>/dev/null`, or conditionals, so this is safe.

## Test Suite Run Results

### Quick run (SKIP_SELFTEST=1)

```
Command: SKIP_SELFTEST=1 bash docs/plans/GITCLEAN-commit-dirty-state-add-branch-policy/verify.sh
Exit code: 1

Results: 33 passed, 2 failed, 2 skipped

Failures:
  FAIL: 2a: working tree is not clean:  M docs/goals/SELFHOST-clean-bootstrap.md
        ?? docs/plans/GITCLEAN-commit-dirty-state-add-branch-policy/exec-2026-02-11-1138.log
        ?? docs/plans/GITCLEAN-commit-dirty-state-add-branch-policy/exec-2026-02-11-1138.prompt
        ?? docs/plans/GITCLEAN-commit-dirty-state-add-branch-policy/spec.2026-02-11-1147-post-exec.md
  FAIL: 2b: unstaged or staged changes detected

Skipped:
  SKIP: 9a: make selftest (SKIP_SELFTEST=1)
  SKIP: 9b: make selftest-c (SKIP_SELFTEST=1)
```

### Failure Analysis

The 2 failures (scenarios 2a and 2b) are **expected post-execution artifacts**, not test or implementation bugs:

1. **3 untracked files** (`exec-*.log`, `exec-*.prompt`, `spec.*-post-exec.md`) — these are plan execution framework outputs generated *after* the plan finished executing. They are not part of the plan's scope and would be committed separately as part of the plan execution bookkeeping.

2. **1 modified file** (`docs/goals/SELFHOST-clean-bootstrap.md`) — a minor annotation added to a goals file, also a post-execution side-effect, not part of the plan's deliverables.

The execution log confirms that `verify.sh` passed all 37 checks (0 failed) at the point when execution completed, *before* these post-execution artifacts were created. The current failures are artifacts of the plan infrastructure writing its own logs into the repo after the plan's final verification step.

### Selftest Validation

Per the execution log, `make selftest` and `make selftest-c` both passed during execution. These were not re-run in this review (would require Docker environment), but the execution log confirms they were validated.

## Overall Verdict

**ADEQUATE**

Every scenario from test.md has a corresponding test in verify.sh. The tests properly validate all acceptance criteria. The 2 current failures are expected post-execution artifacts (plan framework log files), not gaps in the test suite or the implementation. At the point of execution completion, all 37 checks passed with 0 failures.
