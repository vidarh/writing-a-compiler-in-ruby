CASEFIX
Created: 2026-02-10 23:27

# Fix case_spec.rb Crash to Unlock Full Test Execution

[FUNCTIONALITY] Investigate and fix the crash in `case_spec.rb` that kills the process after 11 of ~40 tests, preventing the remaining tests from running and the summary from printing.

## Goal Reference

[COMPLANG](../../goals/COMPLANG-compiler-advancement.md)

## Root Cause

The [case_spec.rb](../../../rubyspec/language/case_spec.rb) spec file currently runs 11 tests (10 pass, 1 fail) before the compiled binary crashes, classified as CRASH in [rubyspec_language.txt](../../rubyspec_language.txt). The crash occurs at a specific test boundary -- the 12th test in the file triggers behavior (likely a splat expansion in `when` clauses, an `eval` call, or a `===` dispatch on an unimplemented type) that causes the compiled binary to segfault or hit a fatal error.

The `case` construct itself works well (10/11 pass rate for executed tests), but the crash at test 12 prevents approximately 30 additional tests from running. Many of these untested cases are likely to pass given the strong pass rate so far, because they test basic case patterns (lists of values, nested case, no-target case) that the compiler already handles.

The specific crash point needs investigation (run the spec, identify test 12, use GDB if segfault), but the root cause is one of: (a) missing method or operator invoked by a particular when pattern, (b) splat expansion in when clauses not fully implemented, or (c) an `eval`/`raise` test that triggers undefined behavior.

## Infrastructure Cost

Zero external infrastructure. This is a compiler or core library fix validated by the existing test suite (`make selftest`, `make selftest-c`, `./run_rubyspec rubyspec/language/case_spec.rb`). No build system changes, no new tools, no Docker modifications.

## Scope

**In scope:**
- Run [case_spec.rb](../../../rubyspec/language/case_spec.rb) and identify exactly which test causes the crash (test 12 in execution order)
- Use GDB to diagnose the crash if it is a segfault
- Fix the root cause in the compiler ([compiler.rb](../../../compiler.rb), [compile_control.rb](../../../compile_control.rb)) or core library ([lib/core/](../../../lib/core/)) as appropriate
- Validate with `make selftest`, `make selftest-c`, and re-running case_spec.rb
- Update [rubyspec_language.txt](../../rubyspec_language.txt) with improved results

**Out of scope:**
- Fixing unrelated test failures within case_spec.rb (the 1 existing failure may remain)
- Fixing other spec files, even if they share the same root cause (those are future plans)
- Parser or architectural changes to the case construct itself (it works for 10/11 tests already)

## Expected Payoff

- case_spec.rb moves from CRASH (11 tests run) to FAIL or PASS (up to ~40 tests run)
- If many of the unblocked tests pass, the per-file status could flip to PASS (4/78 instead of 3/78)
- Individual test case pass count increases (currently 272/994 = 27%)
- Demonstrates the "fix one crash, unlock many tests" pattern for future plans under COMPLANG

## Proposed Approach

1. Run `./run_rubyspec rubyspec/language/case_spec.rb` and identify the last passing test and the first test that triggers the crash
2. Create a minimal reproduction of the crashing test outside the spec framework
3. If segfault, use GDB to get backtrace and identify the crash location
4. Fix the root cause (likely a missing method, bad splat expansion, or unhandled type in `===` dispatch)
5. Validate the fix does not break selftest-c
6. Re-run case_spec.rb and capture improved results

## Prior Plans

- [SPECPICK](../archived/SPECPICK-rubyspec-target-picker/spec.md) -- REJECTED. Was a tooling plan to rank spec files by fix-ROI; mentioned case_spec.rb as an example of a high-ROI target but never proposed actually fixing it. Rejection reason: "aims far too small" and only focused on the existing 78-file language suite. CASEFIX is fundamentally different: it proposes an actual compiler functionality fix rather than a ranking tool.
- [SPECWIDE](../archived/SPECWIDE-broad-rubyspec-baseline/spec.md) -- REJECTED. Proposed building separate automation infrastructure. Rejection reason: "ignored the feedback to reuse the improvement planner." CASEFIX uses the improvement planner directly and targets a concrete compiler fix.

## Acceptance Criteria

- [ ] `./run_rubyspec rubyspec/language/case_spec.rb` no longer reports CRASH status -- it reports FAIL or PASS
- [ ] The total test count (T:) for case_spec.rb increases from 11 to at least 30 (indicating the crash no longer blocks subsequent tests)
- [ ] `make selftest` and `make selftest-c` both pass after the fix
- [ ] [docs/rubyspec_language.txt](../../rubyspec_language.txt) is updated with new results showing the improved case_spec.rb status

## Open Questions

- Is the crash a segfault (requires GDB) or a Ruby-level error that the test harness should catch?
- Does the fix also improve other CRASH files that share the same root cause? (If so, that is bonus value, not a requirement.)

---
*Status: REJECTED — This hasn't been validated. run_rubyspec wasn't run. It's the entirely wrong focus to create individual plans for unvalidated problems instead of addressing automation*