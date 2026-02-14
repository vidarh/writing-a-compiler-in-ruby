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

- [x] Every `@bug` marker in the codebase (currently 22 across 14 files) is categorized and tested
  NOTE: 25 markers identified (revised from 22). All categorized. Marker 23 (transform.rb:911 E[] wrapper) marked "not re-verified" with no spec — but it is an internal DSL construct untestable via mspec. emitter.rb:419 lacks "See spec/..." reference (other emitter markers have it).
- [x] At least one mspec test in `spec/` exists for each distinct root-cause category, demonstrating whether the bug reproduces
  NOTE: 7 spec files cover 7 testable categories (Cat 1-7). Category 8 (miscellaneous) has no dedicated spec but its markers are out-of-scope, duplicates, or internal constructs untestable via mspec.
- [x] All workarounds for confirmed-stale bugs are removed and `make selftest` + `make selftest-c` pass
  NOTE: 2 workarounds physically removed (xdividend, compile_ary_do). 2 additional STALE markers (compile_case_test, build_class_scopes_for_class) had @bug comments removed but methods kept for practical reasons. Cannot independently verify selftest/selftest-c — Docker unavailable in verification environment. Execution log claims both pass.
- [ ] A summary table in the plan log lists each marker with its file, line, category, and status (STALE/CONFIRMED)
  FAIL: log.md contains only 16 lines of session metadata — no summary table. The required table exists in exec-2026-02-14-0306.log (with correct columns: marker#, file, line, category, status, evidence) but was never written to log.md. The execution agent noted this gap: "plan says to update log.md but instructions say not to write to log.md."

## Open Questions

- Some markers describe the same underlying bug (e.g., variable-name collision appears in 5+ places). Should stale-bug removal be all-or-nothing per category, or can individual markers be removed independently if they pass in isolation?

## Implementation Details

### Complete @bug Marker Inventory (26 markers across 14 files)

Grouped by root-cause category:

#### Category 1: Yield/block.call in nested contexts (4 markers)

| # | File | Line | Description | Workaround |
|---|------|------|-------------|------------|
| 1 | [emitter.rb](../../emitter.rb):409 | `yield does not work here` | `block.call(c.reg)` instead of `yield c.reg` |
| 2 | [emitter.rb](../../emitter.rb):417 | `yield does not work here` | `block.call(r)` instead of `yield r` |
| 3 | [globals.rb](../../globals.rb):46 | `This gets turned into calling "comma"` | `block.call(f[0],f[1])` instead of `yield f[0],f[1]` |
| 4 | [compile_calls.rb](../../compile_calls.rb):323 | Block forwarding + yield interaction | Comment-only warning, no code workaround |

**Test construct**: Method that takes `&block` and uses `yield` inside nested blocks/lambdas (e.g., `with_register` style). Also test `yield` with multiple arguments.

**Spec file**: `spec/bug_yield_in_nested_block_spec.rb`

#### Category 2: Variable-name collision / env rewrite (7 markers)

| # | File | Line | Description | Workaround |
|---|------|------|-------------|------------|
| 5 | [compiler.rb](../../compiler.rb):619 | `rest` collides with `arg.rest` method call | Renamed to `xrest` |
| 6 | [regalloc.rb](../../regalloc.rb):310 | Variable name matching method name in lambda | Renamed `reg` → `xreg` |
| 7 | [compile_comparisons.rb](../../compile_comparisons.rb):9 | `op` var picked up instead of block param | Renamed `op` → `o` at call site |
| 8 | [output_functions.rb](../../output_functions.rb):57 | Arg name collides with method name | Comment-only warning (no active rename visible) |
| 9 | [lib/core/enumerator.rb](../../lib/core/enumerator.rb):64 | `range` arg triggers range constructor rewrite | Renamed arg to `r` |
| 10 | [compile_arithmetic.rb](../../compile_arithmetic.rb):122 | `dividend` set incorrectly in nested lambda | Renamed `dividend` → `xdividend` |
| 11 | [function.rb](../../function.rb):123 | `r` not set to `nil` without explicit init | Added explicit `r = nil` |

**Test construct**: Method with a local variable named the same as a method on `self` or a widely-used method, used inside a block/lambda. E.g., a method `rest` on a class, with a local var `rest` inside a block passed to another method. Also test string interpolation referencing outer-scope vars from inside nested blocks.

**Spec file**: `spec/bug_variable_name_collision_spec.rb`

#### Category 3: Ternary expression evaluation (2 markers)

| # | File | Line | Description | Workaround |
|---|------|------|-------------|------------|
| 12 | [treeoutput.rb](../../treeoutput.rb):235 | Ternary `||` evaluates to false in compiler | Expanded to `if/else` |
| 13 | [treeoutput.rb](../../treeoutput.rb):262 | Ternary causes selftest-c failure | Expanded to `if/else` |

**Test construct**: Ternary with `||` in condition; ternary assigning to a variable used in a method call chain. Existing [spec/ternary_operator_bug_spec.rb](../../spec/ternary_operator_bug_spec.rb) covers basic ternary — need to add `||` in condition variant.

**Spec file**: `spec/bug_ternary_expression_spec.rb`

#### Category 4: block_given? in nested lambdas (1 marker)

| # | File | Line | Description | Workaround |
|---|------|------|-------------|------------|
| 14 | [compile_arithmetic.rb](../../compile_arithmetic.rb):115 | `block_given?` doesn't work in nested lambdas | Captured to local `bg = block_given?` before entering block |

**Test construct**: Method with `&block` that checks `block_given?` inside a nested `do` block.

**Spec file**: `spec/bug_block_given_nested_spec.rb`

#### Category 5: Self-recursive lambda / method extraction (3 markers)

| # | File | Line | Description | Workaround |
|---|------|------|-------------|------------|
| 15 | [compiler.rb](../../compiler.rb):563 | Self-recursive lambda extracted to method | `compile_case_test` was a lambda in `compile_case` |
| 16 | [compile_class.rb](../../compile_class.rb):113 | `compile_ary_do` extracted for eigenclass | Wraps `exps.each { compile_do }` in separate method |
| 17 | [transform.rb](../../transform.rb):1088 | `build_class_scopes_for_class` extracted | Split out as workaround for compiler bug |

**Test construct**: Self-recursive lambda assigned to a local, and a lambda that iterates and calls a method, both used inside a method. The recursive case is the most distinctive.

**Spec file**: `spec/bug_self_recursive_lambda_spec.rb`

#### Category 6: Parser divergence between MRI and self-hosted (2 markers)

| # | File | Line | Description | Workaround |
|---|------|------|-------------|------------|
| 18 | [parser.rb](../../parser.rb):797 | MRI needs `E[pos].concat(ret)` for Arrays, self-hosted doesn't | Conditional `elsif ret.is_a?(Array)` branch |
| 19 | [compiler.rb](../../compiler.rb):1231 | `@e.with_local(vars.size+1)` parsed incorrectly | Pre-computed to `s = vars.size + 2` |

**Test construct**: These are parser-level issues, harder to test via mspec. Marker 19 also overlaps with `with_local` not working (marker 20). Validation is via `make selftest-c` comparison.

**Spec file**: `spec/bug_parser_divergence_spec.rb` (tests method call with arithmetic in argument)

#### Category 7: Break / control-flow in register allocation (1 marker)

| # | File | Line | Description | Workaround |
|---|------|------|-------------|------------|
| 20 | [regalloc.rb](../../regalloc.rb):316 | `break` resets ebx incorrectly | `break` commented out; uses `if !free` guard instead |

**Test construct**: `break` inside a block that iterates; verify the broken register state. This may be observable via a test that uses many registers + `break`.

**Spec file**: `spec/bug_break_in_block_spec.rb`

#### Category 8: Miscellaneous / structural (4 markers)

| # | File | Line | Description | Workaround |
|---|------|------|-------------|------------|
| 21 | [emitter.rb](../../emitter.rb):399 | `rescue` not supported (exception handling) | **OUT OF SCOPE** — requires exception support |
| 22 | [compiler.rb](../../compiler.rb):1236 | `with_local` doesn't work, uses `with_stack` | Uses `with_stack(s)` instead of `with_local(vars.size+1)` |
| 23 | [transform.rb](../../transform.rb):911 | Removing `E[]` causes segfault | `E[:sexp, ...]` wrapping kept as workaround |
| 24 | [examples/yieldnest.rb](../../examples/yieldnest.rb):11 | Yield rewrite in main scope fails | Example file, not compiler source |
| 25 | [regalloc.rb](../../regalloc.rb):303 | Workaround for `break` bug below | Guard `if !free` instead of `break` |

Marker 21 is explicitly out of scope. Marker 24 is in `examples/`, not compiler source — note but don't create a separate spec (it's a variant of Category 1). Marker 22 overlaps with Category 6 marker 19. Marker 25 is a duplicate of marker 20.

### Key patterns and conventions

- **Spec format**: All specs must use mspec format with `require_relative '../rubyspec/spec_helper'` and `describe/it/.should` structure
- **Naming**: `spec/bug_<category>_spec.rb` for new specs
- **Run specs**: `./run_rubyspec spec/<file>.rb` to test individual specs
- **Validation after workaround removal**: `make selftest && make selftest-c` (both must pass)
- **Functions to modify**: When removing workarounds:
  - Replace `block.call(...)` with `yield(...)` in [emitter.rb](../../emitter.rb) and [globals.rb](../../globals.rb)
  - Restore original variable names (`xrest` → `rest`, `xreg` → `reg`, `o` → `op`, `xdividend` → `dividend`, `r` → `range`)
  - Restore ternary expressions in [treeoutput.rb](../../treeoutput.rb)
  - Inline extracted methods back if feasible (`compile_ary_do` → direct `exps.each`, `compile_case_test` → lambda)
  - Remove explicit `r = nil` in [function.rb](../../function.rb):124 if no longer needed
  - Restore `break` in [regalloc.rb](../../regalloc.rb):317

### Safety and ordering

- Each category should be tested independently before removing workarounds
- Within a category, individual markers CAN be removed independently (answer to Open Question) — a marker is stale if its specific construct compiles correctly
- Always run `make selftest` before `make selftest-c` (selftest is faster, catches most issues)
- If a workaround removal breaks selftest, immediately revert that specific change before trying the next marker
- The `rescue` workaround (marker 21) is explicitly skipped — it requires exception support

## Execution Steps

1. [ ] **Establish baseline** — Run `make selftest && make selftest-c` to confirm the current codebase passes before any changes. Record pass/fail status.

2. [ ] **Create Category 1 spec: yield in nested blocks** — Write `spec/bug_yield_in_nested_block_spec.rb` testing: (a) a method that takes `&block` and calls `yield` from inside a nested `do` block, (b) `yield` with multiple arguments from a nested block, (c) `yield` from inside a method that itself received a block via `&block`. Run with `./run_rubyspec spec/bug_yield_in_nested_block_spec.rb`.

3. [ ] **Create Category 2 spec: variable-name collision** — Write `spec/bug_variable_name_collision_spec.rb` testing: (a) local variable named `rest` inside a block on an object with a `rest` method, (b) local variable named `reg` inside a lambda on an object with a `reg` method, (c) string interpolation `"set#{op.to_s}"` where `op` is an outer-scope variable referenced inside a block, (d) argument named `range` in a method. Run with `./run_rubyspec spec/bug_variable_name_collision_spec.rb`.

4. [ ] **Create Category 3 spec: ternary expressions** — Write `spec/bug_ternary_expression_spec.rb` testing: (a) `a || b ? c : d` evaluation, (b) ternary with variable assignment on left side used in subsequent method call, (c) ternary inside an `elsif` branch. Run with `./run_rubyspec spec/bug_ternary_expression_spec.rb`.

5. [ ] **Create Category 4 spec: block_given? in nested lambdas** — Write `spec/bug_block_given_nested_spec.rb` testing: a method with `&block` that checks `block_given?` inside a nested `do`/`each` block. Run with `./run_rubyspec spec/bug_block_given_nested_spec.rb`.

6. [ ] **Create Category 5 spec: self-recursive lambda** — Write `spec/bug_self_recursive_lambda_spec.rb` testing: (a) a self-recursive lambda assigned to a local variable, (b) a method containing a lambda that iterates and calls another method on `self`. Run with `./run_rubyspec spec/bug_self_recursive_lambda_spec.rb`.

7. [ ] **Create Category 6 spec: parser divergence** — Write `spec/bug_parser_divergence_spec.rb` testing: (a) method call with arithmetic expression as argument (e.g., `obj.method(x.size + 1)`), (b) conditional position assignment to arrays. Run with `./run_rubyspec spec/bug_parser_divergence_spec.rb`.

8. [ ] **Create Category 7 spec: break in block** — Write `spec/bug_break_in_block_spec.rb` testing: `break` inside an `each` block where the block also uses registers/variables heavily. Run with `./run_rubyspec spec/bug_break_in_block_spec.rb`.

9. [ ] **Analyze spec results and categorize markers** — For each spec, record whether it passes or fails. Build the summary table with columns: marker#, file, line, category, status (STALE if spec passes, CONFIRMED if spec fails). Write initial results to [log.md](log.md).

10. [ ] **Remove stale workarounds: Category 1 (yield/block.call)** — If Category 1 spec passes: in [emitter.rb](../../emitter.rb):410 replace `r = block.call(c.reg)` with `r = yield(c.reg)`, in [emitter.rb](../../emitter.rb):418 replace `block.call(r)` with `yield(r)` (also remove `&block` param from `with_register_for` signature), in [globals.rb](../../globals.rb):48 replace `block.call(f[0],f[1])` with `yield(f[0],f[1])` (also remove `&block` param and uncomment original yield line). Run `make selftest && make selftest-c`. Revert individual changes if they break.

11. [ ] **Remove stale workarounds: Category 2 (variable-name collision)** — If Category 2 spec passes: in [compiler.rb](../../compiler.rb):619-641 rename `xrest` back to `rest`, in [regalloc.rb](../../regalloc.rb):312 rename `xreg` back to `reg`, in [compile_comparisons.rb](../../compile_comparisons.rb):7-14 rename `o` back to `op` and restore `"set#{op.to_s}"`, in [compile_arithmetic.rb](../../compile_arithmetic.rb):120-130 rename `xdividend` back to `dividend`, in [lib/core/enumerator.rb](../../lib/core/enumerator.rb):66 rename `r` back to `range`, in [function.rb](../../function.rb):124 remove explicit `r = nil`. Test each file change individually with `make selftest && make selftest-c`. Revert any that break.

12. [ ] **Remove stale workarounds: Category 3 (ternary)** — If Category 3 spec passes: in [treeoutput.rb](../../treeoutput.rb):235-248 restore `args = comma || block ? flatten(rightv) : rightv`, in [treeoutput.rb](../../treeoutput.rb):262-267 restore `args = lv ? lv + rightv : rightv`. Run `make selftest && make selftest-c`.

13. [ ] **Remove stale workarounds: Category 4 (block_given?)** — If Category 4 spec passes: in [compile_arithmetic.rb](../../compile_arithmetic.rb):118 remove `bg = block_given?` and use `block_given?` directly at line 134. Run `make selftest && make selftest-c`.

14. [ ] **Remove stale workarounds: Category 5 (extracted methods)** — If Category 5 spec passes: consider inlining `compile_case_test` back into `compile_case` as a lambda (in [compiler.rb](../../compiler.rb):563-589), inlining `compile_ary_do` into `compile_eigenclass` (in [compile_class.rb](../../compile_class.rb):113-118,173), and inlining `build_class_scopes_for_class` back into the caller (in [transform.rb](../../transform.rb):1088-1089). These are riskier refactors — test each individually. Run `make selftest && make selftest-c`.

15. [ ] **Remove stale workarounds: Category 6 (parser)** — If Category 6 spec passes: in [compiler.rb](../../compiler.rb):1235-1239 restore `@e.with_local(vars.size+1) do` and remove intermediate `s` variable. The [parser.rb](../../parser.rb):797 divergence is harder to remove (both paths are needed for MRI compatibility) — update the comment to clarify status. Run `make selftest && make selftest-c`.

16. [ ] **Remove stale workarounds: Category 7 (break)** — If Category 7 spec passes: in [regalloc.rb](../../regalloc.rb):316-317 uncomment `break` and remove the `if !free` guard at line 303-304. Run `make selftest && make selftest-c`.

17. [ ] **Update remaining @bug comments** — For each CONFIRMED marker: update the comment to include (a) the date of last verification, (b) a reference to the spec file (e.g., `# See spec/bug_yield_in_nested_block_spec.rb`), (c) a brief description of the failure mode.

18. [ ] **Remove @bug comments from fixed markers** — For each STALE marker where the workaround was successfully removed: delete the `@bug`/`FIXME @bug` comment lines entirely.

19. [ ] **Final validation** — Run `make selftest && make selftest-c` one final time. Run `make spec` to verify all new spec files pass. Run `./run_rubyspec spec/bug_*_spec.rb` to confirm spec status matches expectations.

20. [ ] **Write summary to log** — Update [log.md](log.md) with: (a) the full summary table of all markers with final status, (b) count of markers removed vs confirmed, (c) list of spec files created, (d) any unexpected findings.

---
*Status: APPROVED (implicit via --exec)*