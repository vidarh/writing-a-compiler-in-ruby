EXCMOD
Created: 2026-02-16 04:04
Created: 2026-02-16

# Extract Exception/Rescue Compilation into compile_rescue.rb

[CLEANUP] Extract the exception handling compilation methods from [compiler.rb](../../compiler.rb) into a new [compile_rescue.rb](../../compile_rescue.rb) module, following the established compile_*.rb pattern. This reduces compiler.rb from 1640 to ~1350 lines and isolates exception compilation logic into a focused, maintainable module.

## Goal Reference

[SELFHOST](../../goals/SELFHOST-clean-bootstrap.md)

Also advances [MULTIARCH](../../goals/MULTIARCH-architecture-support.md) indirectly: decomposing compiler.rb into smaller modules is the prerequisite for extracting architecture-specific code, as called out in README.md:28-29 ("General cleanup. The code has gotten messy. Decompose into simpler components.").

## Root Cause

[compiler.rb](../../compiler.rb) is 1640 lines and mixes at least 7 distinct compilation concerns: initialization, argument resolution, constant management, exception/rescue compilation, case/when compilation, assignment compilation, vtable infrastructure, and the main expression dispatcher. The exception/rescue group is the largest coherent block that doesn't already have its own file.

The exception/rescue methods span two non-contiguous regions:

**Region 1** (lines 423-733) — exception primitives:
- `compile_rescue` (423-428): backward-compatibility stub
- `compile_raise` (435-443): raise statement compilation
- `compile_stackframe` (653-656): stack frame pointer access
- `compile_caller_stackframe` (660-664): caller frame for break support
- `compile_stackpointer` (666-669): stack pointer access
- `compile_addr` (674-678): label address for exception dispatch
- `compile_preturn` (682-700): proc return via exception-like stack unwinding
- `compile_unwind` (704-733): exception stack unwinding

**Region 2** (lines 949-1174) — begin/rescue/ensure block compilation:
- `compile_block` (949-960): entry point, delegates to rescue handlers
- `compile_begin_rescues` (965-994): multiple rescue clause handling
- `build_rescue_conditional` (998-1051): conditional chain builder
- `compile_begin_rescue` (1057-1174): main rescue/ensure compilation

Together these 12 methods total ~290 lines of code. They form a self-contained group: they call each other and share the exception-handling concept, but their callers in compiler.rb only invoke them through `compile_block`, `compile_raise`, `compile_preturn`, and `compile_unwind` — all of which are dispatched via the keyword table.

The existing codebase already has 7 `compile_*.rb` extraction files following this exact pattern:
- [compile_calls.rb](../../compile_calls.rb) (515 lines)
- [compile_class.rb](../../compile_class.rb) (469 lines)
- [compile_control.rb](../../compile_control.rb) (365 lines)
- [compile_arithmetic.rb](../../compile_arithmetic.rb) (230 lines)
- [compile_include.rb](../../compile_include.rb) (87 lines)
- [compile_comparisons.rb](../../compile_comparisons.rb) (43 lines)
- [compile_pragma.rb](../../compile_pragma.rb) (24 lines)

Each of these reopens `class Compiler` and adds methods. The extraction follows this proven pattern exactly.

## Infrastructure Cost

Zero. This is a file-level refactoring that moves existing methods into a new file using Ruby's open-class mechanism (`class Compiler ... end`). No API changes, no new dependencies, no build system changes. The only integration point is adding `require 'compile_rescue'` to [compiler.rb](../../compiler.rb) alongside the other `require 'compile_*'` statements at lines 17-23. Validation uses existing `make selftest`, `make selftest-c`, and `make spec`.

## Scope

**In scope:**
- Create [compile_rescue.rb](../../compile_rescue.rb) that reopens `class Compiler` with the 12 exception-related methods
- Move these methods from [compiler.rb](../../compiler.rb):
  - `compile_rescue` (line 423)
  - `compile_raise` (line 435)
  - `compile_stackframe` (line 653)
  - `compile_caller_stackframe` (line 660)
  - `compile_stackpointer` (line 666)
  - `compile_addr` (line 674)
  - `compile_preturn` (line 682)
  - `compile_unwind` (line 704)
  - `compile_block` (line 949)
  - `compile_begin_rescues` (line 965)
  - `build_rescue_conditional` (line 998)
  - `compile_begin_rescue` (line 1057)
- Add `require 'compile_rescue'` to [compiler.rb](../../compiler.rb) at line 23 (after `compile_control`)
- Validate with `make selftest`, `make selftest-c`, and `make spec`

**Out of scope:**
- Extracting other method groups (case/when, assignment, vtable) — those are future cleanup plans
- Refactoring the exception compilation logic itself — this is a pure move, no behavior changes
- Modifying any method signatures or call sites
- Touching any file other than compiler.rb and the new compile_rescue.rb

## Expected Payoff

- [compiler.rb](../../compiler.rb) shrinks from 1640 to ~1350 lines (~18% reduction), making the remaining code easier to navigate
- Exception/rescue compilation logic is isolated in one file, making it easier to understand, debug, and modify independently
- Follows the established compile_*.rb decomposition pattern, reducing the mental model needed to work with the compiler
- The extraction itself validates that the compiler handles this code organization pattern correctly during self-hosting (a subtle SELFHOST test)
- Sets a precedent for further extractions (case/when, assignment, vtable) that would bring compiler.rb closer to a reasonable size (~500-600 lines)
- Advances the README.md goal: "General cleanup. The code has gotten messy. Decompose into simpler components."

## Proposed Approach

1. Create [compile_rescue.rb](../../compile_rescue.rb) with `class Compiler` and all 12 methods, preserving their exact current implementation with no changes.
2. Remove the 12 methods from [compiler.rb](../../compiler.rb).
3. Add `require 'compile_rescue'` to [compiler.rb](../../compiler.rb) at line 23.
4. Run `make selftest` to verify the compiler still works.
5. Run `make selftest-c` to verify self-hosting still works (the self-compiled compiler must also handle the new file layout).
6. Run `make spec` to verify no spec regressions.

## Acceptance Criteria

- [ ] [compile_rescue.rb](../../compile_rescue.rb) exists and contains all 12 exception-related methods (`compile_rescue`, `compile_raise`, `compile_stackframe`, `compile_caller_stackframe`, `compile_stackpointer`, `compile_addr`, `compile_preturn`, `compile_unwind`, `compile_block`, `compile_begin_rescues`, `build_rescue_conditional`, `compile_begin_rescue`)
- [ ] [compiler.rb](../../compiler.rb) no longer contains any of these 12 methods (verified by grep)
- [ ] [compiler.rb](../../compiler.rb) contains `require 'compile_rescue'` alongside the other compile_* requires
- [ ] `make selftest` passes
- [ ] `make selftest-c` passes
- [ ] `make spec` passes
- [ ] [compiler.rb](../../compiler.rb) is under 1400 lines (verified by `wc -l`)

---
*Status: PROPOSAL - Awaiting approval*
