ASGMOD
Created: 2026-02-17

# Extract Assignment Compilation into compile_assignment.rb

[CLEANUP] Extract all assignment-related compilation methods from [compiler.rb](../../compiler.rb) into a new [compile_assignment.rb](../../compile_assignment.rb) module, following the established compile_*.rb pattern. This reduces compiler.rb by ~195 lines and isolates the assignment/destructuring logic into a focused, maintainable module.

## Goal Reference

[SELFHOST](../../goals/SELFHOST-clean-bootstrap.md)

Also advances the README.md goal: "General cleanup. The code has gotten messy. Decompose into simpler components."

## Prior Plans

- **[EXCMOD](../EXCMOD-extract-exception-compilation/spec.md)** (Status: PROPOSAL): Proposes extracting exception/rescue methods from compiler.rb into compile_rescue.rb. EXCMOD targets a different, non-overlapping set of methods (rescue/raise/unwind at lines 423-443, 702-733, 962-1174). This plan targets the assignment methods (lines 445-495, 770-914). The two extractions are independent — they touch different methods and can be executed in either order. Line numbers will shift after whichever runs first, but both plans identify methods by name, not line number.

## Root Cause

[compiler.rb](../../compiler.rb) is 1,640 lines and mixes at least 7 distinct compilation concerns. The assignment group is a large, coherent block consisting of:

**Compound assignment operators** (lines 445-495, 51 lines total):
- `compile_decr` (445-447): `-=` operator
- `compile_incr` (449-451): `+=` operator
- `compile_mul_assign` (453-455): `*=` operator
- `compile_div_assign` (457-459): `/=` operator
- `compile_mod_assign` (461-463): `%=` operator
- `compile_pow_assign` (465-467): `**=` operator
- `compile_and_bitwise_assign` (469-471): `&=` operator
- `compile_or_bitwise_assign` (473-475): `|=` operator
- `compile_xor_assign` (477-479): `^=` operator
- `compile_lshift_assign` (481-483): `<<=` operator
- `compile_rshift_assign` (485-487): `>>=` operator
- `compile_and_assign` (489-493): `&&=` operator

**Main assignment method** ([compiler.rb:770-914](../../compiler.rb), 145 lines):
- `compile_assign` — handles simple variable assignment, instance variable assignment, constant assignment, scoped constant assignment (`Foo::Bar = x`), setter method delegation (`foo.bar = x` → `foo.bar=(x)`), indexed assignment (`foo[i] = x` → `foo.[]=(i, x)`), destructuring assignment, and runtime constant assignment.

Together these 13 methods total ~195 lines. All 12 compound assignment operators delegate to `compile_assign`, making this a self-contained group with a clear internal dependency: the compound operators are thin wrappers around the core `compile_assign` method.

**External callers of `compile_assign` (will continue to work after extraction):**
- [compile_pragma.rb:11](../../compile_pragma.rb) — symbol assignment
- [compile_control.rb:88](../../compile_control.rb) — or-assignment (`||=`)
- [compiler.rb:1138](../../compiler.rb) — rescue variable assignment (in `compile_begin_rescue`)

All callers invoke `compile_assign` as a method on the `Compiler` instance. Since the extracted file reopens `class Compiler`, these calls work unchanged.

**Methods explicitly excluded from this extraction:**
- `compile_and` (line 496): Short-circuit boolean `&&`, not an assignment. Delegates to `compile_if`.
- `combine_types` (line 501): Type inference utility used across many compilation methods.

**Existing compile_*.rb files follow this exact pattern:**
- [compile_calls.rb](../../compile_calls.rb) (515 lines)
- [compile_class.rb](../../compile_class.rb) (469 lines)
- [compile_control.rb](../../compile_control.rb) (365 lines)
- [compile_arithmetic.rb](../../compile_arithmetic.rb) (230 lines)
- [compile_include.rb](../../compile_include.rb) (87 lines)
- [compile_comparisons.rb](../../compile_comparisons.rb) (43 lines)
- [compile_pragma.rb](../../compile_pragma.rb) (24 lines)

## Infrastructure Cost

Zero. This is a file-level refactoring that moves existing methods into a new file using Ruby's open-class mechanism (`class Compiler ... end`). No API changes, no new dependencies, no build system changes. The only integration point is adding `require 'compile_assignment'` to [compiler.rb](../../compiler.rb) alongside the other `require 'compile_*'` statements at lines 17-23. Validation uses existing `make selftest`, `make selftest-c`, and `make spec`.

## Scope

**In scope:**
- Create [compile_assignment.rb](../../compile_assignment.rb) that reopens `class Compiler` with the 13 assignment methods
- Move these methods from [compiler.rb](../../compiler.rb):
  - `compile_decr` (line 445)
  - `compile_incr` (line 449)
  - `compile_mul_assign` (line 453)
  - `compile_div_assign` (line 457)
  - `compile_mod_assign` (line 461)
  - `compile_pow_assign` (line 465)
  - `compile_and_bitwise_assign` (line 469)
  - `compile_or_bitwise_assign` (line 473)
  - `compile_xor_assign` (line 477)
  - `compile_lshift_assign` (line 481)
  - `compile_rshift_assign` (line 485)
  - `compile_and_assign` (line 489)
  - `compile_assign` (line 770)
- Add `require 'compile_assignment'` to [compiler.rb](../../compiler.rb) at line 23 (after `compile_control`)
- Validate with `make selftest`, `make selftest-c`, and `make spec`

**Out of scope:**
- Moving `compile_and`, `combine_types`, or any other non-assignment method
- Extracting other method groups (case/when, constants, vtable) — those are future cleanup plans
- Refactoring the assignment compilation logic itself — this is a pure move, no behavior changes
- Modifying any method signatures or call sites
- Touching any file other than compiler.rb and the new compile_assignment.rb

## Expected Payoff

- [compiler.rb](../../compiler.rb) shrinks from 1,640 to ~1,445 lines (~12% reduction), making the remaining code easier to navigate
- Assignment compilation logic is isolated in one file, making it easier to understand, debug, and modify independently (particularly the complex `compile_assign` method with its 6 different assignment modes)
- Combined with [EXCMOD](../EXCMOD-extract-exception-compilation/spec.md), compiler.rb would shrink to ~1,195 lines (~27% total reduction from both extractions)
- Follows the established compile_*.rb decomposition pattern consistently
- The extraction validates that the compiler handles this code organization pattern correctly during self-hosting
- Direct advancement of [SELFHOST](../../goals/SELFHOST-clean-bootstrap.md) via codebase decomposition, and the README.md goal: "General cleanup. The code has gotten messy. Decompose into simpler components."

## Proposed Approach

1. Create [compile_assignment.rb](../../compile_assignment.rb) with `class Compiler` and the 13 assignment methods, preserving their exact current implementation (including all comments and FIXMEs) with no changes.
2. Remove the 13 methods from [compiler.rb](../../compiler.rb). Leave `compile_and`, `combine_types`, and all other methods in place.
3. Add `require 'compile_assignment'` to [compiler.rb](../../compiler.rb) at line 23.
4. Run `make selftest` to verify the compiler still works.
5. Run `make selftest-c` to verify self-hosting still works (the self-compiled compiler must also handle the new file layout).
6. Run `make spec` to verify no spec regressions.

## Acceptance Criteria

- [ ] [compile_assignment.rb](../../compile_assignment.rb) exists and contains exactly the 13 assignment methods: `compile_assign`, `compile_incr`, `compile_decr`, `compile_mul_assign`, `compile_div_assign`, `compile_mod_assign`, `compile_pow_assign`, `compile_and_bitwise_assign`, `compile_or_bitwise_assign`, `compile_xor_assign`, `compile_lshift_assign`, `compile_rshift_assign`, `compile_and_assign`
- [ ] [compile_assignment.rb](../../compile_assignment.rb) does NOT contain `compile_and`, `combine_types`, or any non-assignment method
- [ ] [compiler.rb](../../compiler.rb) no longer contains any of the 13 extracted methods (verified by grep)
- [ ] [compiler.rb](../../compiler.rb) still contains `compile_and` and `combine_types`
- [ ] [compiler.rb](../../compiler.rb) contains `require 'compile_assignment'` alongside the other compile_* requires
- [ ] `make selftest` passes
- [ ] `make selftest-c` passes
- [ ] `make spec` passes

---
*Status: PROPOSAL - Awaiting approval*
