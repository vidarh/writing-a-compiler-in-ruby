# Test Specification: PLANGUIDE

## Test Suite Location

No new test files are needed in `test/` or `spec/`. This plan creates and
edits documentation files only — there is no executable code to unit test.

All verification is performed by a single shell script:
`tools/check_planguide.sh`

This follows the existing pattern of `tools/check_selftest.sh` for
file-level validation scripts.

## Design Requirements

No abstractions, interfaces, or refactoring are needed. The deliverables
are static markdown files. Testability is inherent — the acceptance
criteria are fully verifiable by checking file existence, content patterns,
and the git diff.

## Required Test Coverage

The shell script `tools/check_planguide.sh` must verify every acceptance
criterion. Each check must print a PASS/FAIL line and the script must exit
non-zero if any check fails.

### 1. File existence

- `docs/improvement-planner.md` exists and is non-empty.

### 2. Required sections present

- File contains a top-level heading (`# `) for the planner guidance.
- File contains a "Do NOT propose" heading (case-insensitive match for
  `do not propose`).
- File contains a "DO propose" heading (case-insensitive match for
  `do propose`).
- File contains a section describing the investigation workflow (match
  for `run_rubyspec` — proving it tells the planner how to run specs).
- File contains a section describing validation requirements (match for
  `make selftest`).

### 3. Forbidden content absent

- File does NOT contain the string `investigate-spec`.
- File does NOT contain the string `validate-fix`.
- File does NOT contain the string `create-minimal-test`.

### 4. README.md reference

- `README.md` contains the literal line `@docs/improvement-planner.md`.

### 5. No unintended modifications

- `git diff --name-only` (against HEAD) lists only `README.md` and
  `docs/improvement-planner.md` as modified/added files (plus this plan's
  own files under `docs/plans/`). Specifically, none of the following
  appear in the diff:
  - `CLAUDE.md`
  - `Makefile`
  - Any file matching `.claude/skills/*`
  - Any file matching `rubyspec/*`

### Edge cases

- The `@docs/improvement-planner.md` line in README.md must be on its own
  line (not embedded inside a markdown bullet or sentence). Verify with a
  regex anchored to line start: `^@docs/improvement-planner.md$`.
- The guidance file must be under 120 lines (the plan targets ~80; 120 is
  a generous upper bound to prevent bloat).

## Mocking Strategy

No mocking is needed. All checks are against local files using standard
shell commands (`test -f`, `grep`, `wc -l`, `git diff`). No network
access, no compilation, no external services.

## Invocation

```bash
bash tools/check_planguide.sh
```

Exit code 0 on success, non-zero on any failure. Each check prints a
one-line result (e.g., `PASS: docs/improvement-planner.md exists`).

## Known Pitfalls

1. **Do not run `make selftest` or `make selftest-c` as part of this
   test.** This plan modifies no compiler code. Running the full build
   would waste time and introduce unrelated failures.

2. **The `git diff` check must account for the test script itself.**
   `tools/check_planguide.sh` will appear in the diff if it is a new
   file. The check should allowlist it (and files under `docs/plans/`).

3. **grep for forbidden strings must search the guidance file only**, not
   README.md or the plan spec. The strings `investigate-spec` etc.
   legitimately appear in the plan documents — only
   `docs/improvement-planner.md` must be free of them.

4. **Case sensitivity on headings.** The plan says `### Do NOT propose`
   and `### DO propose` but does not mandate exact heading level. The
   check should match the words case-insensitively, not the exact
   markdown heading syntax.

5. **The README.md `@` reference must be a bare line.** A grep for the
   string appearing inside a sentence (e.g., `See @docs/...`) would be a
   false positive. Anchor the match to start-of-line.
