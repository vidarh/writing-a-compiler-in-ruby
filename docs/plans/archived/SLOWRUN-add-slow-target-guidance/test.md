# SLOWRUN Test Specification

## Nature of the Change

This plan is a **documentation-only change** — it edits two existing Markdown
files. There is no application code, no new interfaces, no external
dependencies, and no runtime behavior to mock. Traditional unit tests with
mocks are not applicable.

The appropriate automated verification is **content assertion tests**: scripts
that read the modified files and confirm the required content is present.

## Test Suite Location

`docs/plans/SLOWRUN-add-slow-target-guidance/verify.sh`

A single shell script. This follows the project convention of keeping
plan-related artefacts inside the plan directory.

## Design Requirements

None. The targets are plain text files read with standard tools (grep). No
abstractions, interfaces, or refactoring are needed.

## Required Test Coverage

The script must verify all four acceptance criteria from the plan. Each
check must produce a clear PASS/FAIL line and the script must exit non-zero
if any check fails.

### Checks for `docs/improvement-planner.md`

1. **Slow-targets section exists** — The file contains a heading (H2) whose
   text includes "Slow Targets" (case-insensitive).

2. **Targets listed as slow / re-run only for validation** — The section
   body contains language indicating that `make rubyspec-*` targets are slow
   AND should only be re-run to validate code changes (not to inspect
   current state). Verify by checking for both the phrase `make rubyspec`
   and a phrase matching "only.*re-run" or "only.*run.*validat" or
   equivalent (use a generous regex — the exact wording is up to the
   implementer).

3. **Read-the-file guidance** — The file instructs agents to read
   `docs/rubyspec_*.txt` (or the individual filenames) for current state.
   Check for at least one of: `rubyspec_language.txt`,
   `rubyspec_integer.txt`, or `rubyspec_regexp.txt` appearing in the file.

4. **Auto-write / no-manual-pipe warning** — The file states that targets
   automatically write to the results files (via `tee` or equivalent
   phrasing) and warns against manually piping output. Check for the word
   `tee` or the phrase `automatically write` (or similar) in the file.

### Checks for `CLAUDE.md`

5. **Slow-target note exists near rubyspec bullets** — The file contains a
   note (within 15 lines of a `make rubyspec-` reference) indicating these
   targets are slow. Check that the word "slow" (case-insensitive) appears
   within the Testing subsection (between `### Testing` and the next `###`
   or `##` heading).

6. **Auto-write-to-file note in CLAUDE.md** — Within the same Testing
   subsection, the file mentions that results are written to
   `docs/rubyspec_*.txt` or references `tee` / automatic output.

### Edge-case checks

7. **No reference to `rubyspec_language_new.txt`** — The new content in
   `docs/improvement-planner.md` must NOT reference the non-standard file
   `rubyspec_language_new.txt`. Grep the file and fail if it appears in the
   new section.

8. **`make spec` not listed as slow** — The new "Slow Targets" section must
   NOT list `make spec` as a slow target. Check that the section text does
   not describe `make spec` as slow.

## Mocking Strategy

Not applicable — tests read local files only. No network access, services,
or credentials required.

## Invocation

```bash
bash docs/plans/SLOWRUN-add-slow-target-guidance/verify.sh
```

Exit code 0 = all checks pass. Non-zero = at least one check failed.

Each check prints a line like:

```
PASS: Slow-targets section exists in improvement-planner.md
FAIL: No auto-write/tee guidance found in improvement-planner.md
```

A summary line at the end reports total passed / total checks.

## Known Pitfalls

- **Do not hard-code exact prose.** The plan specifies content themes, not
  exact sentences. Checks must use flexible patterns (regexes, case-insensitive
  grep) so they pass regardless of minor wording differences.

- **Check the right section, not the whole file.** For CLAUDE.md check 5,
  verify the note is in the Testing subsection — not just anywhere in the
  file. A stray match in an unrelated section would be a false positive.

- **Line-number references in the plan are approximate.** The plan says
  "after line 176" etc., but the execution agent's edits may shift line
  numbers. Tests must not depend on specific line numbers.

- **Do not modify the target files** (`CLAUDE.md`, `docs/improvement-planner.md`)
  from the test script. The script is read-only verification.

- **The verify script itself is not a permanent test.** It validates the
  plan's acceptance criteria after implementation. It does not need to be
  integrated into `make selftest` or `make spec`.
