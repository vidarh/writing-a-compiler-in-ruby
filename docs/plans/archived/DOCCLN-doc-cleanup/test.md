# DOCCLN Test Specification

## Test Suite Location

`docs/plans/DOCCLN-doc-cleanup/verify.sh` — a standalone shell script.

This plan touches only markdown files, so there is no code to unit-test.
The "tests" are acceptance-criteria verifications that check filesystem state
and file contents after the edits are applied. A shell script is the
appropriate vehicle: it requires no test framework, runs without Docker,
and exits non-zero on the first failure.

## Design Requirements

No abstractions or refactoring needed. The verification script reads files
on disk and compares against expected values. All checks use standard POSIX
tools (`test`, `grep`, `wc`).

## Required Test Coverage

### 1. File Deletion (6 scenarios)

Each of the six deleted files must be confirmed absent from the working tree:

| # | File | Notes |
|---|------|-------|
| 1 | `docs/DEVELOPMENT_RULES.md` | Was git-tracked |
| 2 | `docs/RUBYSPEC_INTEGRATION.md` | Was git-tracked |
| 3 | `docs/RUBYSPEC_CRASH_ANALYSIS.md` | Was git-tracked |
| 4 | `docs/REJECTED_APPROACH_METHOD_CHAINING.md` | Was git-tracked |
| 5 | `docs/KERNEL_MIGRATION_PLAN.md` | Was git-tracked |
| 6 | `docs/INVESTIGATION_POSTFIX_IF_BUG.md` | Was untracked |

**Check**: `[ ! -e "$file" ]` for each. Fail with descriptive message if any
file still exists.

### 2. No Broken Cross-References

After deleting files, remaining docs must not reference them as if they
still exist.

- **Scenario 2a**: `docs/control_flow_as_expressions.md` must NOT contain
  a bare reference to `REJECTED_APPROACH_METHOD_CHAINING.md` that reads as
  an active "See ..." directive. Specifically:
  - `grep -c "See REJECTED_APPROACH_METHOD_CHAINING.md"` must return 0.
  - The file *may* mention the name in a "(removed" context — that is fine.
- **Scenario 2b**: `docs/bignums.md` must NOT reference the non-existent
  files `FIXNUM_CLASS_METHOD_INVESTIGATION.md` or
  `FIXNUM_TO_INTEGER_MIGRATION.md`.

### 3. KNOWN_ISSUES.md — No FIXED Items in Active Issues

- **Scenario 3a**: The text `FIXED` must NOT appear between the `## Active Issues`
  heading and the next `##`-level heading (or end of Active Issues section).
  Check: extract the Active Issues section and `grep -ci "FIXED"` — must be 0.
- **Scenario 3b**: The strings `super() Uses Wrong Superclass` and
  `Classes in Lambdas` must NOT appear in the Active Issues section.
- **Scenario 3c**: Active issues must be numbered sequentially starting at 1
  with no gaps. Check that `### 1.`, `### 2.`, `### 3.` headings exist
  and no `### 4.` or `### 5.` heading exists (there should be exactly 3
  remaining active issues).

### 4. KNOWN_ISSUES.md — Spec Counts Match rubyspec_language.txt

Extract the summary line from `docs/rubyspec_language.txt`:
- Passed: 3, Failed: 28, Crashed: 47 (spec file level)
- Total tests: 994, Passed: 272, Failed: 705, Skipped: 17, Pass rate: 27%

**Scenario 4a**: KNOWN_ISSUES.md must contain the string `Passed: 3` (or
equivalent like `PASSED: 3`) for spec file counts.

**Scenario 4b**: KNOWN_ISSUES.md must contain the numbers `28` (failed files)
and `47` (crashed files) in the Current State Summary section.

**Scenario 4c**: KNOWN_ISSUES.md must contain individual test case stats.
At minimum, the numbers `994` (total), `272` (passed), and `27%` (pass rate)
must appear in the file.

### 5. TODO.md — No FIXED Active Items

- **Scenario 5a**: The section `### 1.2 Classes in Lambdas - FIXED` must
  not exist. Check: `grep -c "Classes in Lambdas.*FIXED" docs/TODO.md`
  must return 0.
- **Scenario 5b**: No section heading in the Priority 1/Priority 2 area
  should contain `FIXED`. Check: `grep -c "^### .*FIXED" docs/TODO.md`
  must return 0.

### 6. TODO.md — Spec Counts Match rubyspec_language.txt

Same source-of-truth numbers as scenario 4.

- **Scenario 6a**: TODO.md must contain `28` (failed files) and `47`
  (crashed files) somewhere in its Test Status section.
- **Scenario 6b**: TODO.md must contain individual test stats (`994`, `272`,
  `27%`) somewhere in its Test Status section.

### 7. bignums.md — Size and Content

- **Scenario 7a**: `wc -l < docs/bignums.md` must be under 250.
- **Scenario 7b**: Required section headings must exist. Check for presence
  of each (case-insensitive grep):
  - "status" (current status summary)
  - "memory layout" or "representation" (memory layout section)
  - "phase" (phase summary — at least one mention of phases)
  - "limitation" or "future" (known limitations / future work)
  - "design" or "decision" (design decisions)
  - "method" or "api" (key methods reference)
- **Scenario 7c**: No commit hashes should remain. Check:
  `grep -cE '\b[0-9a-f]{7,40}\b' docs/bignums.md` — if any matches,
  inspect manually, but flag as warning (some hex values may be legitimate
  in memory layout descriptions). A strict check: `grep -c "Commit"
  docs/bignums.md` (case-sensitive) should return 0.
- **Scenario 7d**: No stale file references. `grep -c
  "FIXNUM_CLASS_METHOD_INVESTIGATION\|FIXNUM_TO_INTEGER_MIGRATION"
  docs/bignums.md` must return 0.

### 8. Preserved Files Not Damaged

Files NOT in the deletion list must still exist:

- `docs/ARCHITECTURE.md`
- `docs/DEBUGGING_GUIDE.md`
- `docs/TODO.md`
- `docs/KNOWN_ISSUES.md`
- `docs/bignums.md`
- `docs/control_flow_as_expressions.md`
- `docs/rubyspec_language.txt`

**Check**: `[ -f "$file" ]` for each.

## Mocking Strategy

Not applicable. This plan has no external dependencies, no APIs, no network
access, and no code execution beyond reading files on disk. All checks are
local filesystem assertions.

## Invocation

```bash
bash docs/plans/DOCCLN-doc-cleanup/verify.sh
```

Exits 0 on success, non-zero on first failure. Each check prints a
one-line PASS/FAIL message to stdout before the script exits.

The script must be runnable from the repository root directory
(`/home/vidarh/Desktop/Projects/Compiler`).

## Known Pitfalls

1. **grep exit codes**: `grep -c` returns 1 when count is 0 on some
   systems. Use `grep -c ... || true` and compare the captured count,
   rather than relying on grep's exit status for zero-match checks.

2. **ANSI escape codes in rubyspec_language.txt**: The file contains ANSI
   color codes (e.g., `[32m`). When extracting numbers, strip escapes
   first or use patterns that tolerate them.

3. **Hex false positives in bignums.md**: Memory layout examples may
   contain hex values like `0x3fffffff` that look like commit hashes.
   The commit-hash check (scenario 7c) should grep for `Commit` as a
   keyword rather than raw hex patterns to avoid false positives.

4. **Line count sensitivity**: `wc -l` counts newline-terminated lines.
   If bignums.md has a trailing newline the count is accurate; if not, it
   may be off by one. The 250-line limit has enough margin that this
   should not matter, but be aware.

5. **Section extraction for KNOWN_ISSUES.md**: Scenarios 3a-3c require
   extracting text between `## Active Issues` and the next `##` heading.
   Use `sed -n '/^## Active Issues/,/^## /p'` — this includes both
   boundary lines, which is fine for grep checks.

6. **Do not hard-code rubyspec numbers**: The verification script should
   extract expected values from `docs/rubyspec_language.txt` at runtime
   rather than embedding magic numbers. This ensures the test remains
   valid if rubyspec_language.txt is regenerated before the plan executes.
