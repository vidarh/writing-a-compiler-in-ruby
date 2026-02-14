BUGAUDIT
Created: 2026-02-12 04:02

# Validate and Triage @bug Workarounds in Compiler Source

[CLEANUP] Systematically test all 22 `@bug` markers across 14 files to determine which workarounds are stale, remove confirmed-fixed ones, and document the rest.

## Goal Reference

[SELFHOST](../../goals/SELFHOST-clean-bootstrap.md)

## Root Cause

The compiler source contains 22 `@bug`/`FIXME @bug` markers across 14 files. These mark places where the compiler cannot correctly compile its own constructs, forcing workarounds (e.g., `block.call` instead of `yield`, renamed variables, extracted methods, avoided ternaries). These markers were added incrementally over 2400+ commits as bugs were encountered, but the compiler has evolved significantly since most were introduced. The SELFHOST goal notes: "Many `@bug` and `FIXME` markers are likely outdated." No systematic validation has ever been performed to determine which are still relevant. Every stale workaround that remains is dead complexity that obscures the codebase and misrepresents the compiler's actual capability.

## Infrastructure Cost

Zero. This touches only existing compiler source files and the `spec/` directory. No new tooling, no build system changes, no external dependencies. Validation uses `make selftest` and `make selftest-c`, which are standard development commands.

## Scope

**In scope:**
- Categorize all 22 `@bug` markers by root cause (yield/block, variable-name collision, ternary expression, exception handling, parser, other)
- For each distinct bug category, write a minimal mspec test in `spec/` that exercises the supposedly-broken construct in isolation
- Run each test to determine if the bug still reproduces
- For bugs that no longer reproduce: remove the workaround (replace `block.call` with `yield`, use original variable names, restore ternaries, etc.), then validate with `make selftest` and `make selftest-c`
- For bugs that still reproduce: update the marker comment with current status and leave a reference to the spec file that demonstrates the failure
- Produce a summary in the plan log documenting each marker's status (STALE/CONFIRMED) with evidence

**Out of scope:**
- Fixing confirmed bugs (that is separate plan work under SELFHOST or COMPLANG)
- The `rescue` workaround in [emitter.rb](../../emitter.rb) line 399-401 (requires exception support, a Priority 2 feature)
- Modifying any rubyspec files

## Expected Payoff

- Accurate picture of the compiler's actual self-hosting limitations (currently unknown -- could be 5 real bugs or 20)
- Removal of stale workarounds, reducing code complexity and improving readability
- Spec files documenting each confirmed bug, providing reproducible test cases for future fixes
- Updated `@bug` comments with cross-references to spec files, making each bug actionable
- Direct advancement of [SELFHOST](../../goals/SELFHOST-clean-bootstrap.md) goal

## Proposed Approach

1. Group the 22 markers into ~6 root-cause categories (yield in nested blocks, variable-name rewrite collision, ternary expression evaluation, block_given? in nested lambdas, parser MRI/self-host divergence, miscellaneous)
2. For each category, write one mspec test in `spec/` that isolates the construct (e.g., a method that yields from a nested block, a class with a variable named the same as a method)
3. Run each spec with `./run_rubyspec spec/<test>.rb` to check if the bug reproduces
4. For stale bugs: remove the workaround, run `make selftest` and `make selftest-c`
5. For confirmed bugs: update the comment, add spec file reference
6. Document results in the plan log

## Acceptance Criteria

- [ ] Every `@bug` marker in the codebase (currently 22 across 14 files) is categorized and tested
- [ ] At least one mspec test in `spec/` exists for each distinct root-cause category, demonstrating whether the bug reproduces
- [ ] All workarounds for confirmed-stale bugs are removed and `make selftest` + `make selftest-c` pass
- [ ] A summary table in the plan log lists each marker with its file, line, category, and status (STALE/CONFIRMED)

## Open Questions

- Some markers describe the same underlying bug (e.g., variable-name collision appears in 5+ places). Should stale-bug removal be all-or-nothing per category, or can individual markers be removed independently if they pass in isolation?

---
*Status: APPROVED (implicit via --exec)*