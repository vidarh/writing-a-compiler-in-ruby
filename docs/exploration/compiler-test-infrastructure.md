# Compiler Test Infrastructure & Autonomous AI Enablement
Path: /home/vidarh/Desktop/Projects/Compiler
Explored: 2026-02-10
Last reviewed: 2026-02-10 (updated with crash classification corrections)
Related goals: [COMPLANG](../goals/COMPLANG-compiler-advancement.md)

## What This Is

A Ruby-to-x86 self-hosting compiler with a multi-tiered test infrastructure
designed for incremental spec compliance. The project has 2420 commits, 548
in the last ~3 months, and is actively developed. It targets 32-bit x86 and
runs compilation inside Docker containers (`ruby-compiler-buildenv`, Debian
Buster with GCC multilib and Ruby 2.5).

## Current State

**Active**, with recent work on peephole optimizer, bignum support, and
string methods. Self-hosting works (selftest and selftest-c pass). The main
frontier is language spec compliance: 3/78 spec files fully passing (27%
individual test case pass rate: 272/994).

### Test Tiers

1. **selftest** (`make selftest`) — 804-line self-hosted test in
   [test/selftest.rb](../../test/selftest.rb). Compiles the compiler's
   own test suite with the MRI-compiled compiler, runs the native binary.
   MUST PASS before any commit.

2. **selftest-c** (`make selftest-c`) — Same test compiled by the
   self-compiled compiler (`./compile2`). Validates self-hosting
   correctness. MUST PASS before any commit.

3. **rubyspec-language** (`make rubyspec-language`) — 78 spec files from
   the [Ruby language spec suite](../../rubyspec/language/). Run via
   [run_rubyspec](../../run_rubyspec), which applies sed transformations
   to work around compiler limitations (parenthesization, instance
   variable rewriting, platform guard stripping). Results saved to
   [docs/rubyspec_language.txt](../rubyspec_language.txt).
   Also: `make rubyspec-integer` (67 files), `make rubyspec-regexp` (24 files).

4. **spec/** (`make spec`) — 88 custom mspec-compatible test files in
   [spec/](../../spec/) (2962 total lines). Reduced test cases for
   specific bugs. Run through the same `run_rubyspec` harness.

5. **Peephole unit tests** — [test/test_peephole.rb](../../test/test_peephole.rb)
   (85 lines, Minitest). Tests the peephole optimizer in isolation under
   MRI. Run directly with `ruby test/test_peephole.rb`.

### Compilation Pipeline

Source → Scanner → Parser (recursive descent + Shunting Yard) → AST →
Transformer → Compiler → x86 assembly → GCC (in Docker) → native binary.
Build scripts: [compile](../../compile) (MRI→native),
[compile2](../../compile2) (self-compiled compiler→native).

### Key Metrics

| Metric | Value |
|--------|-------|
| Total commits | 2420 |
| Core compiler LoC | ~6,000 (compiler.rb + compile_*.rb + parser.rb + shunting.rb + emitter.rb) |
| Core library LoC | ~10,600 across 49 files in [lib/core/](../../lib/core/) |
| Rubyspec language files passing | 3/78 (4%) |
| Individual tests passing | 272/994 (27%) |
| Rubyspec language files "crashing" | 47/78 (see note below) |
| Rubyspec language files failing (not crashing) | 28/78 (36%) |
| Rubyspec regexp pass rate | 66/154 (42%) — 2/24 files fully passing |

**Note on "crash" classification**: "CRASH" in run_rubyspec means "no
summary line printed" — it does NOT necessarily mean segfault. Of 47
"crashing" language spec files, 24 actually ran some tests before
crashing (95 tests passed across these files). Only 23 produced truly
zero output. Many "crashes" are mid-test failures (missing methods,
unhandled control flow) rather than segfaults. This distinction matters:
the 24 partial-crash files are nearly as actionable as the 28 FAIL files.

## Key Files

- [compiler.rb](../../compiler.rb) — 1640 lines. Core compiler class, AST walking + codegen.
- [parser.rb](../../parser.rb) — 1276 lines. Recursive descent parser.
- [shunting.rb](../../shunting.rb) — 561 lines. Shunting yard expression parser.
- [emitter.rb](../../emitter.rb) — 748 lines. Assembly output with register allocation.
- [peephole.rb](../../peephole.rb) — 247 lines. Peephole optimizer for x86 assembly patterns.
- [compile_calls.rb](../../compile_calls.rb) — 515 lines. Method call compilation.
- [compile_class.rb](../../compile_class.rb) — 465 lines. Class/module compilation.
- [compile_control.rb](../../compile_control.rb) — 365 lines. Control flow (if/while/case).
- [run_rubyspec](../../run_rubyspec) — 447 lines. Bash script that wraps spec files, applies workarounds, compiles, runs with 30s timeout.
- [rubyspec_helper.rb](../../rubyspec_helper.rb) — 949 lines. Minimal mspec-compatible framework (describe/it/should/matchers/mocks).
- [test/selftest.rb](../../test/selftest.rb) — 804 lines. Self-hosting validation.
- [Makefile](../../Makefile) — Build targets for all test tiers.
- [tools/check_selftest.sh](../../tools/check_selftest.sh) — ASM stability checker (detects non-deterministic codegen).
- [tools/compare_asm.rb](../../tools/compare_asm.rb) — ASM diff tool for peephole development.
- [docs/TODO.md](../TODO.md) — Prioritized bug list and test status.
- [docs/KNOWN_ISSUES.md](../KNOWN_ISSUES.md) — Detailed bug documentation with root causes.
- [docs/rubyspec_runner_limitations.md](../rubyspec_runner_limitations.md) — Documents sed workarounds.

## AI-AGENT AUTONOMOUS WORK ENABLEMENT (HIGH PRIORITY)

This project is the **strongest candidate for autonomous AI improvement** in the codebase.

### Why It's Ideal

1. **Deterministic test output**: `make selftest`, `make selftest-c`, and
   `./run_rubyspec` all produce clear pass/fail output. No ambiguity.
2. **Clear bug catalog**: [docs/TODO.md](../TODO.md) and
   [docs/KNOWN_ISSUES.md](../KNOWN_ISSUES.md) have prioritized bugs with
   root cause analysis, affected specs, and previous fix attempts documented.
3. **Strict guardrails**: [CLAUDE.md](../../CLAUDE.md) prevents dangerous
   shortcuts (no editing rubyspec, no special-casing operators, no reverting
   without saving). These guard against the most common AI mistake patterns.
4. **Self-contained**: Docker provides a reproducible build environment.
   All dependencies are in the image.
5. **Massive headroom**: From 3/78 passing (4%) to hypothetical 78/78 —
   each fix is a measurable improvement.

### Autonomous Workflow Already Exists

The project has custom skills defined:
- `/validate-fix` — runs selftest-c, target specs, regression tests
- `/investigate-spec` — runs a spec, analyzes failures, creates minimal
  test case, proposes fix
- `/create-minimal-test` — creates a standalone test case
- `/fixtodo` — picks and fixes the next TODO item

These skills are designed to let Claude autonomously investigate and fix
failing specs.

### Current Bottleneck: Expanding Rubyspec Coverage

The primary metric is rubyspec compliance. Currently only the language/
suite (78 files) is regularly tracked. The full rubyspec has 3,781 spec
files across language/, core/, library/, and more. Core types with
implementations in lib/core/ (integer: 67 specs, array: 128, hash: 69,
string: 139, regexp: 24, plus nil/true/false/symbol/comparable/kernel:
189) are realistic expansion targets for the run_rubyspec harness.

Of the 47 "crashing" language specs, 24 actually ran partial tests
(95 passed) before failing — these are nearly as actionable as the 28
pure-FAIL files since they produce diagnostic output showing where
the failure occurs.

## Opportunities

- **Systematic crash triage**: The 47 crashing specs likely share common
  root causes (e.g., missing method implementations causing segfaults,
  `break` semantics, exception handling). A triage pass that categorizes
  crashes by root cause (e.g., "missing method X", "block/closure issue",
  "exception not caught") would identify which fixes unblock the most specs.

- **Targeted core library stubs**: Many crashes likely stem from missing
  method implementations in [lib/core/](../../lib/core/). Adding stubs
  that raise or return nil instead of crashing would convert crashes to
  failures, producing more actionable output.

- **run_rubyspec improvements**: The script (448 lines of bash with complex
  sed chains) is fragile. The [limitations are documented](../rubyspec_runner_limitations.md)
  and known. Two specific compiler bugs (no-parens method calls with
  defaults+block, hash literals passed to methods with blocks) necessitate
  most of the sed workarounds.

- **Peephole optimizer expansion**: The [peephole.rb](../../peephole.rb) has
  a solid foundation (247 lines, 8 unit tests) and a
  [detailed plan](../peephole_optimizer_plan.md). The
  [tools/asm_ngram.rb](../../tools/asm_ngram.rb) can identify the most
  common instruction patterns to target. This is a safe area for autonomous
  work since peephole changes are validated by selftest/selftest-c.

- **Spec-by-spec fix workflow**: The 28 failing-but-not-crashing specs
  produce detailed assertion output. An autonomous agent could: (1) run
  a spec, (2) read the failure output, (3) trace the failing assertion
  to a missing/buggy implementation, (4) fix it, (5) verify with
  selftest/selftest-c + the target spec. The `/investigate-spec` and
  `/validate-fix` skills already support this workflow.

## Ideas (not yet plans)

- **Crash root-cause catalog**: Run all 47 "crashing" specs individually,
  capture partial output and crash signals, categorize by common causes.
  Note: 24 of these already produce partial output. This would produce
  a prioritized "fix X to unblock Y specs" map.

- **Failing spec priority matrix**: For the 28 failing specs, count
  how many individual tests pass vs fail. Specs close to passing (e.g.,
  case_spec: 10 pass, 1 fail) are quick wins that would flip file-level
  results from FAIL to PASS.

- **Method coverage gap analysis**: Compare methods called in rubyspec
  language tests against methods implemented in [lib/core/](../../lib/core/).
  Missing methods that appear in many specs are high-value implementation
  targets.

- **Peephole rule mining**: Use `tools/asm_ngram.rb` on `out/selftest.s`
  to identify the top 10 most common 2-instruction and 3-instruction
  patterns. Each pattern is a potential peephole rule. The test
  infrastructure (unit tests + selftest) makes this safe to iterate on.

- **run_rubyspec rewrite in Ruby**: The bash script with chained sed
  transformations is brittle and hard to extend. A Ruby rewrite could
  use the compiler's own parser to do proper AST-level transformations
  instead of regex-based text munging. This would eliminate many false
  failures from sed mangling.
