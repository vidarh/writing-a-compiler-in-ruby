BUGAUDIT2
Created: 2026-03-08 04:01

# Audit and Triage @bug Workaround Markers

**Goal**: [SELFHOST](../../goals/SELFHOST-clean-bootstrap.md)

**Status**: PROPOSED

## Problem Statement

The compiler source contains 22 `@bug` markers across 13 files, each representing a place where the compiler cannot correctly compile a Ruby construct used in its own source. These workarounds date from various stages of development, and the [SELFHOST](../../goals/SELFHOST-clean-bootstrap.md) goal explicitly notes: "Many `@bug` and `FIXME` markers are likely outdated — the compiler has advanced significantly since they were added."

Currently there is no inventory distinguishing stale markers (compiler already fixed, workaround can be removed) from live bugs (construct still broken). This blocks systematic progress on clean self-hosting.

## Root Cause

The `@bug` markers were added incrementally as developers encountered compiler limitations during self-hosting work. No process exists to re-validate them when compiler improvements land. As a result, markers accumulate indefinitely — some protecting against bugs that were fixed months ago, others guarding genuinely broken constructs. Without triage, every marker carries the same implicit weight, and no one knows which workarounds are removable.

The root cause is **missing feedback loop**: compiler improvements don't trigger re-evaluation of existing workarounds.

## Scope

For each of the 22 `@bug` markers in the compiler source (across [compiler.rb](../../compiler.rb), [emitter.rb](../../emitter.rb), [regalloc.rb](../../regalloc.rb), [transform.rb](../../transform.rb), [treeoutput.rb](../../treeoutput.rb), [parser.rb](../../parser.rb), [function.rb](../../function.rb), [globals.rb](../../globals.rb), [compile_arithmetic.rb](../../compile_arithmetic.rb), [compile_calls.rb](../../compile_calls.rb), [compile_comparisons.rb](../../compile_comparisons.rb), [output_functions.rb](../../output_functions.rb), [lib/core/enumerator.rb](../../lib/core/enumerator.rb)):

1. **Read the marker and surrounding code** to understand what construct is being worked around.
2. **Check if a `spec/bug_*_spec.rb` already exists** for this marker (7 specs exist currently).
3. **For markers without specs**: write an mspec test in `spec/` that exercises the original (non-workaround) code path.
4. **Run each spec** under `./run_rubyspec` to classify the marker as:
   - **STALE**: Spec passes — the workaround can be removed.
   - **LIVE**: Spec fails — the bug still exists, workaround is necessary.
5. **For STALE markers**: rewrite the code to remove the workaround, verify with `make selftest && make selftest-c`.
6. **Produce a triage report** at `docs/bug_marker_triage.md` listing every marker with its classification, spec file, and (for LIVE markers) a one-line description of the remaining bug.

### Out of scope

- Fixing LIVE bugs (that's follow-up work for targeted plans like [BGFIX](../BGFIX-fix-block-given-in-nested-blocks/spec.md), [YIELDFIX](../YIELDFIX-fix-yield-in-nested-blocks/spec.md), etc.)
- Auditing the ~200 general `FIXME` comments (separate, larger effort)
- Changes to `rubyspec/` (prohibited by project rules)

## Infrastructure Cost

**Low.** This plan uses only existing infrastructure:
- `spec/` directory and mspec format (already established)
- `./run_rubyspec` test runner (already works for `spec/`)
- `make selftest` and `make selftest-c` (standard validation)
- No new tools, dependencies, or build targets required

## Expected Payoff

- **Workaround removal**: Based on the SELFHOST goal's assessment that "many" markers are outdated, conservatively expect 5-10 of 22 markers to be removable, yielding cleaner, more idiomatic compiler source.
- **Complete spec coverage**: Every `@bug` marker will have a corresponding spec, making regressions detectable.
- **Triage report**: Provides a prioritized list for follow-up SELFHOST work — which bugs remain and what constructs they affect.
- **Incremental SELFHOST progress**: Each removed workaround is a step toward the clean bootstrap vision.

## Prior Plans

No prior plans in `docs/plans/archived/` target `@bug` marker auditing. Several active plans address individual bugs that `@bug` markers reference:
- [BGFIX](../BGFIX-fix-block-given-in-nested-blocks/spec.md) — addresses `compile_arithmetic.rb:115` marker
- [YIELDFIX](../YIELDFIX-fix-yield-in-nested-blocks/spec.md) — addresses `emitter.rb:409,417` markers

This plan complements those by providing the complete inventory they lack.

## Acceptance Criteria

1. Every `@bug` marker in `*.rb` and `lib/core/*.rb` (currently 22 across 13 files) has a corresponding `spec/bug_*_spec.rb` test file.
2. Each spec has been run and the marker classified as STALE or LIVE.
3. All STALE markers have been removed: the workaround code replaced with the original construct, verified by `make selftest` and `make selftest-c` passing.
4. A triage report exists at `docs/bug_marker_triage.md` with one entry per marker containing: file:line, classification (STALE/LIVE), spec file path, and (for LIVE) a one-line bug description.
5. `make selftest` and `make selftest-c` pass after all changes.

## Risks

- **False negatives**: A spec might pass in isolation but the workaround might guard against a bug that only manifests during full self-compilation. Mitigation: always validate removals with `make selftest-c`, not just individual spec runs.
- **Interdependent workarounds**: Removing one workaround might expose a latent failure in another. Mitigation: remove workarounds one at a time, running full validation after each.

---
*Status: PROPOSED*
