# Improvement Planner Guidance

This file provides project-specific guidance for the improvement planner
when running in the compiler project directory.

## Test Infrastructure

The compiler has a tiered test infrastructure:

1. **`make selftest`** / **`make selftest-c`** — Self-hosting validation. Must pass before committing any change.
2. **`./run_rubyspec <path>`** — Universal spec runner. Accepts individual files or directories from anywhere in the spec tree.
3. **`make spec`** — Runs project-specific specs from `spec/`.

The full spec tree is large. `rubyspec/core/` has 50+ subdirectories
(array, hash, string, integer, kernel, comparable, enumerable, etc.),
plus `rubyspec/library/`, `rubyspec/command_line/`, and `spec/` for
project-specific tests. Any file or directory can be passed to
`./run_rubyspec`.

## Slow Targets and Results Files

The `make rubyspec-*` convenience targets are **slow** — each one compiles
and runs dozens of spec files sequentially (with a 30-second timeout per
file), taking many minutes to complete. The three slow targets and their
results files are:

| Target | Results file |
|---|---|
| `make rubyspec-integer` | `docs/rubyspec_integer.txt` |
| `make rubyspec-language` | `docs/rubyspec_language.txt` |
| `make rubyspec-regexp` | `docs/rubyspec_regexp.txt` |

Each target **automatically writes** its output to the corresponding
results file via `tee` (see Makefile). You never need to manually redirect
or pipe the output.

**Rules:**

1. **Read the results files** (`docs/rubyspec_*.txt`) to understand current
   spec status. Do NOT re-run a slow target just to see results — the file
   already contains the latest output from the last run.
2. **Only re-run** `make rubyspec-*` targets to **validate actual code
   changes**. If you have not changed any compiler or library code, there
   is no reason to re-run them.
3. **Never manually pipe** target output to the results file (e.g.,
   `make rubyspec-language > docs/rubyspec_language.txt`). The target
   already writes to that file via `tee` — piping manually wastes time
   and duplicates what the Makefile does automatically.

**Note:** `make spec` (project-specific specs in `spec/`) is fast and does
not have a results file — this guidance applies only to the `make rubyspec-*`
targets listed above.

## Investigation Workflow

Before proposing any plan, follow this workflow:

1. **Pick a spec** — Choose a spec file or directory at random from anywhere in the spec tree. Do not limit yourself to any particular subdirectory.
2. **Run it live** — Execute `./run_rubyspec <path>` and read the actual output.
3. **Identify the root cause** — Determine whether failures come from a compiler bug, a missing `lib/core/` method, or a test framework limitation. Check [KNOWN_ISSUES.md](KNOWN_ISSUES.md) and [TODO.md](TODO.md) for existing context.
4. **Read the source** — Trace the failure through the relevant compiler or library source to understand the code path.
5. **Propose a fix plan** — Ground the plan in the live output and source analysis. Include the spec file(s) tested, the command run, and the output observed.

## Validation Requirements

Every fix plan must include these verification steps:

- Run `make selftest` and `make selftest-c` to confirm no self-hosting regressions.
- Re-run the target spec with `./run_rubyspec` to confirm the fix works.
- Run the parent suite directory (not just the single file) to check for regressions in related specs.

### Do NOT propose

- Fix proposals not grounded in live spec output — run the spec first, then propose.
- Automation-for-automation's-sake or meta-infrastructure plans (new commands, new Makefile targets, results management tooling).
- Plans that modify any file in `rubyspec/` — specs define correct Ruby behavior; fix the compiler, not the spec.
- Plans based on unverified assumptions about the execution environment — check first.

### DO propose

- Any improvement grounded in live test output and source analysis.
- Plans should include the specific spec file(s) tested, the command run, and the output observed when applicable.
