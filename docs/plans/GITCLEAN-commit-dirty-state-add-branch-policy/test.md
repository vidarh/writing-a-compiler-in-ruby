# GITCLEAN Test Specification

## Test Suite Location

`docs/plans/GITCLEAN-commit-dirty-state-add-branch-policy/verify.sh` — a standalone shell script.

This plan touches only git state, markdown files, and CLAUDE.md. There is no
compiler code to unit-test (the only compiler change is `peephole.rb`, which
is already covered by existing `test/test_peephole.rb` and
`test/test_peephole_fixture.rb` minitest suites, plus `make selftest`).
The "tests" are acceptance-criteria verifications that check git state,
filesystem state, and file contents after all commits are applied. A shell
script is the appropriate vehicle.

## Design Requirements

No abstractions or refactoring needed. The verification script uses `git`
commands and standard POSIX tools (`test`, `grep`, `wc`, `sed`) to inspect
repository state. No mocking infrastructure is required.

## Required Test Coverage

### 1. Rubyspec Submodule Is Clean (4 scenarios)

**Scenario 1a**: The rubyspec submodule must not appear as modified in the
parent repo. Check: `git diff --quiet rubyspec` must exit 0 (no output, no
changes).

**Scenario 1b**: Inside the submodule, `git -C rubyspec status --porcelain`
must produce empty output (no modified files, no untracked files).

**Scenario 1c**: The submodule pointer must still reference the originally
committed upstream ref `6267cc7`. Check: `git ls-tree HEAD rubyspec` must
contain `6267cc7`.

**Scenario 1d**: The previously modified tracked files must be at their
upstream state. Specifically, inside `rubyspec/`:
- `git -C rubyspec diff HEAD -- core/integer/fixtures/classes.rb` must
  produce no output
- `git -C rubyspec diff HEAD -- core/integer/shared/abs.rb` must produce
  no output
- `git -C rubyspec diff HEAD -- spec_helper.rb` must produce no output

### 2. Working Tree Is Clean (2 scenarios)

**Scenario 2a**: `git status --porcelain` must produce empty output (no
modified, deleted, untracked, or staged files). This is the master
acceptance criterion for the entire plan.

**Scenario 2b**: `git diff --quiet` and `git diff --cached --quiet` must
both exit 0 (no unstaged changes, no staged changes).

### 3. Thematic Commits Exist (3 scenarios)

**Scenario 3a**: `git log --oneline -10` must show at least 5 distinct
commits (the 5 thematic content commits plus the policy commit). Check:
`git log --oneline -10 | wc -l` must be >= 6.

**Scenario 3b**: Commit messages must cover the expected work streams. Check
that the last 10 commit messages (via `git log --oneline -10`) collectively
contain references to at least 3 of these keywords (case-insensitive):
- "doc" (doc cleanup commit)
- "peephole" (peephole optimizer commit)
- "plan" or "infrastructure" (planning infrastructure commit)
- "tool" or "spec" (new tools/specs commit)
- "policy" or "workflow" or "submodule" (CLAUDE.md policy commit)

**Scenario 3c**: No single commit should contain all the changes. Verify
that no commit in the last 10 touches more than 30 files. Check:
`git log --oneline --stat -10` and ensure no single commit's stat summary
shows more than 30 file changes.

### 4. Deleted Docs Are Gone (5 scenarios)

Each of the five deleted documentation files must not exist:

| # | File |
|---|------|
| 4a | `docs/DEVELOPMENT_RULES.md` |
| 4b | `docs/KERNEL_MIGRATION_PLAN.md` |
| 4c | `docs/REJECTED_APPROACH_METHOD_CHAINING.md` |
| 4d | `docs/RUBYSPEC_CRASH_ANALYSIS.md` |
| 4e | `docs/RUBYSPEC_INTEGRATION.md` |

**Check**: `[ ! -e "$file" ]` for each.

### 5. Planning Infrastructure Committed (3 scenarios)

**Scenario 5a**: `docs/plans/` directory must exist and contain files.
Check: `[ -d docs/plans ]` and `ls docs/plans/ | wc -l` > 0.

**Scenario 5b**: `docs/goals/` directory must exist and contain files.
Check: `[ -d docs/goals ]` and `ls docs/goals/ | wc -l` > 0.

**Scenario 5c**: `docs/exploration/` directory must exist and contain files.
Check: `[ -d docs/exploration ]` and `ls docs/exploration/ | wc -l` > 0.

### 6. New Tools and Specs Committed (3 scenarios)

**Scenario 6a**: `tools/asm_diff_counts.rb` must exist and be tracked.
Check: `[ -f tools/asm_diff_counts.rb ]` and
`git ls-files --error-unmatch tools/asm_diff_counts.rb` exits 0.

**Scenario 6b**: `tools/check_planguide.sh` must exist and be tracked.
Check: `[ -f tools/check_planguide.sh ]` and
`git ls-files --error-unmatch tools/check_planguide.sh` exits 0.

**Scenario 6c**: `spec/minimal_heredoc_spec.rb` must exist and be tracked.
Check: `[ -f spec/minimal_heredoc_spec.rb ]` and
`git ls-files --error-unmatch spec/minimal_heredoc_spec.rb` exits 0.

### 7. CLAUDE.md Contains Rubyspec Submodule Policy (5 scenarios)

All checks target `CLAUDE.md` in the repository root.

**Scenario 7a**: A section heading containing "Rubyspec Submodule" must
exist. Check: `grep -c "Rubyspec Submodule" CLAUDE.md` >= 1.

**Scenario 7b**: The file must state that local modifications to the
submodule are forbidden. Check: at least one of these patterns must match
(case-insensitive): "never modify", "never commit.*rubyspec", "must not.*
modify", "forbid.*changes.*rubyspec".

**Scenario 7c**: The file must mention the aspiration to pass unmodified
upstream rubyspec. Check: `grep -ci "unmodified.*upstream\|upstream.*
unmodified\|pass.*unmodified" CLAUDE.md` >= 1.

**Scenario 7d**: The file must mention that `run_rubyspec` is temporary.
Check: `grep -ci "temporary\|interim" CLAUDE.md` >= 1 in the context of
run_rubyspec or the custom runner.

**Scenario 7e**: The file must state that workarounds must live outside the
submodule. Check: `grep -ci "outside.*submodule\|outside.*rubyspec"
CLAUDE.md` >= 1.

### 8. CLAUDE.md Contains Git Workflow Policy (4 scenarios)

**Scenario 8a**: A section heading containing "Git Workflow" must exist.
Check: `grep -c "Git Workflow" CLAUDE.md` >= 1.

**Scenario 8b**: The policy must require feature branches. Check:
`grep -ci "feature branch" CLAUDE.md` >= 1.

**Scenario 8c**: The policy must require committing work before starting new
tasks. Check: `grep -ci "commit.*before\|before.*start\|clean.*before"
CLAUDE.md` >= 1.

**Scenario 8d**: The policy must require a clean working tree. Check:
`grep -ci "clean.*working.*tree\|working.*tree.*clean\|clean.*before.*new"
CLAUDE.md` >= 1.

### 9. Compiler Still Works (2 scenarios)

**Scenario 9a**: `make selftest` must pass (exit 0). This validates that
the peephole.rb changes and any other committed modifications do not break
the compiler.

**Scenario 9b**: `make selftest-c` must pass (exit 0). This validates the
self-compiled compiler still works after all changes.

### 10. No Rubyspec Files Were Modified (1 scenario)

**Scenario 10a**: The junk files that were inside `rubyspec/` before cleanup
must not exist. Spot-check a representative sample:
- `[ ! -e rubyspec/compiler_stubs.rb ]`
- `[ ! -e rubyspec/simple_tests ]`
- `[ ! -e rubyspec/test_bignum_basic.rb ]`
- `[ ! -e rubyspec/temp_bignum_plus_test.rb ]`

## Mocking Strategy

Not applicable. This plan has no external dependencies, no APIs, no network
access, and no code execution beyond git commands and file reading. All
checks are local repository state assertions.

## Invocation

```bash
# Full verification (includes selftest — slow):
bash docs/plans/GITCLEAN-commit-dirty-state-add-branch-policy/verify.sh

# Quick verification (skip selftest):
SKIP_SELFTEST=1 bash docs/plans/GITCLEAN-commit-dirty-state-add-branch-policy/verify.sh
```

Exits 0 on success, non-zero on first failure. Each check prints a
one-line PASS/FAIL message to stdout.

The script must be runnable from the repository root directory
(`/home/vidarh/Desktop/Projects/Compiler`).

The selftest scenarios (9a, 9b) should be gated behind a `SKIP_SELFTEST`
environment variable so the structural checks can run quickly during
development. When `SKIP_SELFTEST=1`, scenarios 9a and 9b are skipped with
a SKIP message.

## Known Pitfalls

1. **grep exit codes**: `grep -c` returns exit code 1 when the match count
   is 0 on some systems. Use `grep -c ... || true` and compare the captured
   count numerically, rather than relying on grep's exit status for
   zero-match assertions.

2. **Submodule pointer format**: `git ls-tree HEAD rubyspec` outputs a line
   like `160000 commit 6267cc7... rubyspec`. The verification must match
   the short hash `6267cc7` (not the full 40-char hash) since that is what
   the plan references. Use `grep 6267cc7` on the ls-tree output.

3. **Running selftest requires Docker or i386 toolchain**: The `make
   selftest` and `make selftest-c` targets require the build environment.
   If run outside Docker, they will fail for infrastructure reasons, not
   code reasons. The `SKIP_SELFTEST` escape hatch handles this.

4. **Commit count depends on execution**: The plan calls for 5-6 thematic
   commits. The exact number may vary slightly if the execution agent
   groups changes differently. Scenario 3a checks for >= 6 commits in the
   last 10, but should tolerate minor variations (e.g., 5 commits if two
   groups are merged). The key invariant is "more than 1 commit" — a single
   giant dump fails the test.

5. **CLAUDE.md policy wording**: The grep patterns in scenarios 7 and 8 are
   intentionally flexible (multiple alternatives, case-insensitive) because
   the execution agent writes the policy text. Do not use overly specific
   patterns that would break on reasonable paraphrasing. However, the
   section headings ("Rubyspec Submodule" and "Git Workflow") should match
   exactly since the plan specifies them.

6. **Order of operations matters**: The verification script should check
   git cleanliness (scenarios 1-2) first, then commit structure (scenario
   3), then file content (scenarios 4-8), then compiler correctness
   (scenario 9). If git state is wrong, file content checks are meaningless.

7. **Do not run verify.sh before the plan executes**: The script verifies
   post-execution state. Running it on the current dirty working tree will
   produce failures for scenarios 1-3, which is expected and correct.

8. **Peephole changes have existing test coverage**: The execution agent
   should run the existing minitest suite (`ruby test/test_peephole.rb` and
   `ruby test/test_peephole_fixture.rb`) after committing peephole changes,
   in addition to `make selftest`. These are fast MRI-based unit tests and
   catch regressions immediately.
