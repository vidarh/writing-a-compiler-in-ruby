# Test Adequacy Report: PLANGUIDE

## Test File

`tools/check_planguide.sh` — 134 lines, shell script.

## Test Suite Run Results

**Command:** `bash tools/check_planguide.sh`
**Exit code:** 0
**Output:**
```
PASS: docs/improvement-planner.md exists and is non-empty
PASS: Top-level heading present
PASS: "Do NOT propose" section present
PASS: "DO propose" section present
PASS: Investigation workflow references run_rubyspec
PASS: Validation requirements reference make selftest
PASS: No forbidden string 'investigate-spec'
PASS: No forbidden string 'validate-fix'
PASS: No forbidden string 'create-minimal-test'
PASS: README.md contains @docs/improvement-planner.md on its own line
PASS: No unintended file modifications
PASS: Guidance file is 48 lines (under 120 limit)

All checks passed.
```

- **Result:** 12/12 checks passed, 0 failures

## Scenario Coverage: test.md Scenarios

| # | test.md Scenario | Test Present? | Would Fail if Broken? |
|---|---|---|---|
| 1 | File existence: `docs/improvement-planner.md` exists and is non-empty | YES (line 17) | YES — `test -s` fails on missing/empty file |
| 2a | Required section: top-level heading (`# `) | YES (line 24) | YES — `head -1 \| grep '^# '` fails without it |
| 2b | Required section: "Do NOT propose" (case-insensitive) | YES (line 30, `grep -qi`) | YES |
| 2c | Required section: "DO propose" (case-insensitive) | YES (line 36, `grep -qi`) | YES |
| 2d | Required section: investigation workflow (`run_rubyspec`) | YES (line 42) | YES |
| 2e | Required section: validation requirements (`make selftest`) | YES (line 48) | YES |
| 3a | Forbidden content: `investigate-spec` absent | YES (line 55) | YES — inverted grep catches presence |
| 3b | Forbidden content: `validate-fix` absent | YES (line 61) | YES — same mechanism |
| 3c | Forbidden content: `create-minimal-test` absent | YES (line 67) | YES — same mechanism |
| 4 | README.md contains `@docs/improvement-planner.md` on own line | YES (line 74, `grep -qx`) | YES — `-x` requires full-line match |
| 5a | No modification to `CLAUDE.md` | YES (line 94) | YES |
| 5b | No modification to `Makefile` | YES (line 99) | YES |
| 5c | No modification to `.claude/skills/*` | YES (line 104) | YES |
| 5d | No modification to `rubyspec/*` | YES (line 109) | YES |
| Edge 1 | `@` reference on its own line (not embedded) | YES (`grep -qx` anchors to full line) | YES |
| Edge 2 | Guidance file under 120 lines | YES (lines 119-123) | YES |

**All 16 scenarios from test.md have corresponding test checks.**

## Additional Acceptance Criteria from spec.md

The plan spec contains acceptance criteria beyond what test.md specified.
These are checked here by manual inspection and assessed for regression risk:

| Acceptance Criterion | Automated Test? | Manual Verification | Regression Risk |
|---|---|---|---|
| File does NOT reference results files (`rubyspec_language.txt` etc.) | **NO** | Verified: no results file references present | Low — file is static docs |
| File does NOT direct planner to only a subset of specs | **NO** | Verified: line 24 says "Do not limit yourself to any particular subdirectory" | Low |
| File does NOT prohibit `.claude` changes | **NO** | Verified: no `.claude` prohibition present | Low |
| File does NOT prohibit documentation-only plans | **NO** | Verified: no such prohibition present | Low |
| File does NOT reference `bin/improve` | **NO** | Verified: string absent | Low |

These 5 criteria are "negative" constraints (file must NOT contain X) where
the current file passes by omission. While automated checks would improve
regression protection, the test.md specification itself did not require them,
and the risk is low for static documentation files.

## External Dependencies

None. All checks use local shell commands (`test -f`, `grep`, `wc -l`,
`git diff`). No network access, no compilation, no external services.
No mocking needed or used. Correct per test spec.

## Minor Issues (non-blocking)

1. **Dead code in unintended-modifications check.** Lines 84-91 contain a
   `case` statement that matches known-good files but every branch falls
   through to `;;` with no action. The actual checking happens in the
   subsequent `grep` blocks (lines 94-112). The `case` block is harmless
   but misleading — it appears to be scaffolding that was never completed.

2. **Shell error on missing file.** When `docs/improvement-planner.md`
   does not exist, the `wc -l` check (line 119) produces a shell error
   because `wc -l` receives no input. The script still exits non-zero
   (earlier checks already fail), but the error message is cosmetic noise.

## Verdict

**ADEQUATE**

All 16 scenarios from test.md are covered by automated checks. Tests
correctly pass on the current implementation and would correctly fail if
the implementation were reverted or broken. No external dependencies.
5 additional acceptance criteria from spec.md lack automated tests but
pass manual verification and represent low regression risk for static
documentation files. The test.md specification itself did not require
these additional checks.
