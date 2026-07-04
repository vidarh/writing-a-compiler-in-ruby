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

## Sweep Results and Slow Runs

Full-tree sweep results are kept in **`docs/spec_status.md`** (human-readable
summary) and **`docs/spec_status.jsonl`** (one JSON record per spec file:
outcome, pass/fail/skip counts). They are written by the parallel runner
(`make specs-parallel`, which drives `tools/run_specs_parallel.rb`), and
`tools/classify_failures.rb` clusters the jsonl by failure signature.

**Rules:**

1. **Read `docs/spec_status.md` / `.jsonl`** to understand current spec
   status. Do NOT launch a sweep just to see results — the files contain the
   latest completed sweep.
2. **A full sweep is slow** (~2,150 files; the better part of an hour even in
   parallel). Only re-run it to measure the aggregate effect of actual code
   changes; for a single fix, `./run_rubyspec <file-or-dir>` on the affected
   specs is the right validation.
3. Per-file compile/run timeouts (COMPILE_TIMEOUT / SPEC_TIMEOUT, defaults
   120s/30s) mean hangs surface as COMPILE_FAIL/TIMEOUT outcomes rather than
   stalling a run.

**Note:** `make spec` (project-specific specs in `spec/`) is fast and has no
results file. Also read **`docs/review/ANALYSIS.md`** — the current ranked
failure triage and work plan; plans that duplicate an item already ranked
there should reference it.

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
