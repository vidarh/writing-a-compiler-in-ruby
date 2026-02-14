# RubySpec Compliance Landscape
Path: /home/vidarh/Desktop/Projects/Compiler
Explored: 2026-02-10
Last reviewed: 2026-02-14
Related goals: [COMPLANG](../goals/COMPLANG-compiler-advancement.md)

## What This Is

A detailed analysis of the compiler's rubyspec compliance: what runs, what
doesn't, the meaning of the metrics used, and the path toward broader
coverage. This note corrects several misleading framings in earlier
documentation and refocuses on the more relevant metric of overall rubyspec
compliance rather than per-file crash/pass classification.

## Current State

### Tracked Suites

Three rubyspec suites are currently tracked via Makefile targets:

| Suite | Files | Pass (file) | Individual pass rate | Results file |
|-------|-------|-------------|---------------------|--------------|
| language/ | 80 | 4 (5%) | 269/982 (27%) | [rubyspec_language.txt](../rubyspec_language.txt) |
| core/regexp/ | 24 | 2 (8%) | 66/154 (42%) | [rubyspec_regexp.txt](../rubyspec_regexp.txt) |
| core/integer/ | 67 | >=5 (truncated) | unknown (results truncated) | [rubyspec_integer.txt](../rubyspec_integer.txt) |

**Note**: The integer results file is truncated at 9 lines (only shows first
5 specs, all passing). A complete run hasn't been captured recently.

### The Full Rubyspec Universe

The rubyspec git submodule contains **3,773 spec files** across:
- `language/` — 66 raw files / 80 as counted by runner (currently tracked)
- `core/` — 2,079 files (only integer/ and regexp/ tracked)
- `library/` — large (not tracked)
- `command_line/`, `security/`, `optional/` — not tracked

### Correcting the "47 of 78 Crash" Framing

The existing documentation (TODO.md, KNOWN_ISSUES.md, COMPLANG goal)
prominently features "47 of 78 spec files crash (60%)" (now 48 of 80). This number is
misleading in several ways:

1. **"CRASH" doesn't mean segfault.** In [run_rubyspec](../../run_rubyspec)
   (line 256), "CRASH" means "no summary line `passed.*failed.*skipped` was
   printed." This includes: actual segfaults, 30-second timeouts, infinite
   loops, mid-test fatal errors from missing methods, and control flow bugs
   that abort the test binary before the summary line is printed.

2. **Many of 48 "crash" files actually ran tests successfully.** They produced
   partial results before the test binary exited without printing the summary
   line. Examples from recent runs:
   - `until_spec.rb`: 23 passed, 5 failed, then crashed
   - `array_spec.rb`: 13 passed, 9 failed, then crashed
   - `case_spec.rb`: 10 passed, 1 failed, then crashed
   - `string_spec.rb`: 13 passed, 14 failed, then crashed

3. **A subset truly produced zero test output** (P:0 F:0 S:0 T:0).
   These are the genuinely opaque failures.

4. **The 48/80 metric focuses on the wrong denominator.** The rubyspec has
   3,773 files. Tracking 78 (language/) captures only 2% of the suite. The
   more relevant questions are:
   - Of all rubyspec files, how many can the runner+compiler even attempt?
   - Of those attempted, what's the individual test pass rate?

5. **A second results file exists with different numbers.**
   [rubyspec_language_new.txt](../rubyspec_language_new.txt) shows results
   from an earlier run without the sed workarounds: 12 COMPILE FAILs, 39
   crashes, 25 fails, 3 pass (79 files, 158/993 = 15%). With workarounds
   the current run shows 269/982 = 27%, confirming workarounds provide
   significant value.

### The Custom Runner Architecture

The spec compliance pipeline has three layers:

1. **[run_rubyspec](../../run_rubyspec)** (447-line bash script): Wraps each
   spec file with preprocessing:
   - Replaces `require_relative 'spec_helper'` with `require 'rubyspec_helper'`
   - Wraps spec body in `def run_specs; ...; end; run_specs; print_spec_results`
   - Inlines fixture files and shared example files
   - Applies sed transformations for compiler bug workarounds
   - Compiles the transformed file, runs with 30s timeout
   - Classifies results as PASS/FAIL/CRASH/COMPILE FAIL

2. **[rubyspec_helper.rb](../../rubyspec_helper.rb)** (949 lines): Minimal
   mspec reimplementation providing:
   - `describe`/`it`/`before`/`after`/`context`/`let`
   - `should`/`should_not` with matchers (==, eql, equal, be_true/false/nil,
     raise_error, be_an_instance_of, be_kind_of, be_close, include, complain)
   - Mock framework (should_receive, and_return, and_raise, method_missing)
   - ScratchPad, SpecEvaluate stubs
   - Guard stubs (ruby_version_is, platform_is, ruby_bug, etc.)
   - Helper functions (bignum_value, fixnum_max/min, c_long_size)
   - Stubs: ruby_exe (returns ""), complain matcher (skips)

3. **Sed workarounds** ([documented](../rubyspec_runner_limitations.md)):
   - Add parens to `describe`/`it_behaves_like` (bug: no-parens + defaults + block = segfault)
   - Rewrite `@ivar` to `$spec_ivar` (no instance_eval)
   - Strip args from `platform_is`/`ruby_bug`/etc. (hash literals in method+block = crash)
   - Replace `.and_return([])` with `.and_return(nil)` (empty array literal crash)
   - Convert `shared: true` keyword syntax to `{:shared => true}`

### Path to Unmodified mspec

Running specs through the real mspec framework requires the compiler to
handle mspec's Ruby code. The standard `spec_helper.rb` expects:
- `File.respond_to?`, `File.realpath`, `File.expand_path`
- `require 'mspec'` (loading mspec gem)
- `Thread.report_on_exception=`
- Full Ruby standard library compatibility

This is far beyond current capabilities. The custom runner is the pragmatic
approach for the foreseeable future.

## Key Files

- [run_rubyspec](../../run_rubyspec) — 447 lines. Custom bash test harness.
- [rubyspec_helper.rb](../../rubyspec_helper.rb) — 949 lines. mspec reimplementation.
- [rubyspec/spec_helper.rb](../../rubyspec/spec_helper.rb) — 44 lines. Real mspec loader (not used).
- [rubyspec/compiler_stubs.rb](../../rubyspec/compiler_stubs.rb) — 26 lines. Minimal stubs.
- [rubyspec/default.mspec](../../rubyspec/default.mspec) — mspec configuration showing suite structure.
- [docs/rubyspec_runner_limitations.md](../rubyspec_runner_limitations.md) — Sed workaround documentation.
- [docs/rubyspec_language.txt](../rubyspec_language.txt) — Latest language suite results.
- [docs/rubyspec_language_new.txt](../rubyspec_language_new.txt) — Results without sed workarounds.
- [docs/rubyspec_regexp.txt](../rubyspec_regexp.txt) — Regexp suite results (42% pass rate).
- [docs/rubyspec_integer.txt](../rubyspec_integer.txt) — Integer suite results (truncated).

## Opportunities

- **Expand tracked suites**: The runner already works with any rubyspec
  directory (e.g., `./run_rubyspec rubyspec/core/nil/`). Adding Makefile
  targets for core/nil, core/true, core/false, core/symbol, and
  core/comparable would track compliance for types that are likely to have
  high pass rates since their implementations exist in [lib/core/](../../lib/core/).
  These are small suites (nil: ~10 files, true: ~5 files, false: ~5 files)
  that would provide quick signal.

- **Fix the integer results truncation**: The `rubyspec_integer.txt` file
  shows only 5 of 67 spec files (all passing). Running `make rubyspec-integer`
  and committing the full results would reveal the actual integer compliance
  rate, which is likely one of the highest since integer.rb is one of the
  most complete implementations.

- **Reclassify "CRASH" files with partial output**: The files that run
  partial tests before crashing are nearly as actionable as the 27 FAIL files.
  The runner could report a 4th category: "PARTIAL" (ran some tests but
  didn't print summary). This would make the metrics more honest and direct
  attention to the actually-opaque 23 zero-output failures.

- **Identify the last test before crash for partial-crash files**: For
  files that produce partial output, the last `[P:X F:Y S:Z]` line
  before the crash identifies exactly which test causes the crash. This
  gives immediate debugging targets without needing any crash triage — the
  data is already in the output.

- **Core library spec expansion**: The compiler implements 49 types in
  lib/core/. Rubyspec core/ has specs for most of these. Cross-referencing
  which implemented types have untested rubyspec suites would identify
  the lowest-effort coverage expansions. Candidate sizes:
  - core/nil/: small, likely high pass rate
  - core/true/: small, likely high pass rate
  - core/false/: small, likely high pass rate
  - core/symbol/: moderate, partial implementation exists
  - core/comparable/: moderate, implementation exists
  - core/array/: 128 specs, large but implementation is extensive
  - core/hash/: 69 specs, implementation exists
  - core/string/: 139 specs, implementation exists
  - core/kernel/: 131 specs, critical but many missing methods

- **Correct documentation metrics**: TODO.md, KNOWN_ISSUES.md, and the
  COMPLANG goal may still say "47 crashing" without noting that many
  produce useful partial output. The "4/80 passing (5%)" metric undersells
  progress — the individual test pass rate (27%) and the partial-crash
  data tell a much richer story.

## Ideas (not yet plans)

- **Composite compliance dashboard**: Instead of tracking file-level
  pass/fail/crash, track individual test pass rate across all attempted
  suites. A single "X of Y individual tests passing across N files
  attempted" metric is more meaningful than "3 of 78 files pass."

- **Quick-win suite expansion**: Run the runner against core/nil/,
  core/true/, core/false/ and capture results. These are tiny suites
  (~20 combined files) with simple implementations that likely have
  high pass rates — they would demonstrate that the compiler handles
  more of rubyspec than the language/ suite alone suggests.

- **Partial-crash-to-fail conversion**: For the files that crash
  mid-test, wrapping the `run_specs` call in a more robust error handler
  in rubyspec_helper.rb could catch some failures and print the summary
  line, converting CRASH to FAIL. This doesn't fix the underlying bugs
  but makes the results more informative.

- **Sed workaround impact analysis**: Compare rubyspec_language.txt
  (with workarounds, 269/982 pass = 27%) against rubyspec_language_new.txt
  (without workarounds). The delta quantifies the value of the sed
  transformations and identifies which compiler bugs, if fixed, would
  make the workarounds unnecessary.

- **Near-passing file identification**: From the results, files that are
  one failure away from full-pass (e.g., case_spec: 10 pass, 1 fail but
  classified as CRASH) are the highest-ROI fix targets. A script that
  parses rubyspec_language.txt and ranks files by (total - passed) would
  produce a prioritized fix list.
