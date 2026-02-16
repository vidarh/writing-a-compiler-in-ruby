EXCMOD
Created: 2026-02-16 04:04
Created: 2026-02-16

# Extract Exception/Rescue Compilation into compile_rescue.rb

[CLEANUP] Extract the exception/rescue compilation methods from [compiler.rb](../../compiler.rb) into a new [compile_rescue.rb](../../compile_rescue.rb) module, following the established compile_*.rb pattern. This reduces compiler.rb by ~250 lines and isolates the rescue/ensure compilation logic into a focused, maintainable module.

## Goal Reference

[SELFHOST](../../goals/SELFHOST-clean-bootstrap.md)

Also advances [MULTIARCH](../../goals/MULTIARCH-architecture-support.md) indirectly: decomposing compiler.rb into smaller modules is the prerequisite for extracting architecture-specific code, as called out in README.md:28-29 ("General cleanup. The code has gotten messy. Decompose into simpler components.").

## Root Cause

[compiler.rb](../../compiler.rb) is 1640 lines and mixes at least 7 distinct compilation concerns: initialization, argument resolution, constant management, exception/rescue compilation, case/when compilation, assignment compilation, vtable infrastructure, and the main expression dispatcher. The exception/rescue group is a large coherent block that doesn't already have its own file.

The methods that are *specifically* about exception/rescue compilation are:

**Rescue stubs and raise** (lines 423-443):
- `compile_rescue` (423-428): backward-compatibility stub for rescue dispatch
- `compile_raise` (430-443): compiles raise statement into Kernel#raise call

**Exception unwinding** (lines 702-733):
- `compile_unwind` (702-733): exception stack unwinding — restores ebp/esp from a handler object and jumps to the rescue label

**Begin/rescue/ensure block compilation** (lines 962-1174):
- `compile_begin_rescues` (962-994): transforms multiple rescue clauses into a single catch-all with conditional dispatch
- `build_rescue_conditional` (996-1051): builds the if/elsif chain that checks exception class for multi-rescue blocks
- `compile_begin_rescue` (1053-1174): main rescue/ensure compilation — sets up handler, try block, rescue label, ensure clause

Together these 6 methods total ~250 lines of code. They form a self-contained group: they call each other and share the exception-handling concept. The only entry points from outside are `compile_rescue`, `compile_raise`, and `compile_unwind` (dispatched via the keyword table), plus `compile_begin_rescues` and `compile_begin_rescue` which are called by `compile_block`.

**Methods explicitly excluded from this extraction:**

Several methods in the same region of compiler.rb are *not* exception-specific and must remain:

- `compile_block` (949-960): The general entry point for `:block` nodes (begin/end and do/end blocks). It dispatches to rescue handling only when rescue/ensure clauses are present; otherwise it just calls `compile_do`. It is the block compilation entry point, not an exception method.
- `compile_preturn` (682-700): Proc/block return semantics. It unwinds to the defining scope's stack frame so that `return` inside a proc exits the enclosing method. This is block/closure control flow, not exception handling — it is analogous to `compile_unwind` in mechanism but serves a different language feature (proc return vs exception rescue).
- `compile_stackframe` (653-656): Returns the current frame pointer (ebp). Used by lambda/proc creation (transform.rb:302), main function init (compiler.rb:1352), *and* exception handling. A general-purpose low-level primitive.
- `compile_caller_stackframe` (660-664): Returns the caller's saved frame pointer. Used by Proc#call for break support. Not exception-specific.
- `compile_stackpointer` (666-669): Returns the current stack pointer (esp). Used by exception handling's `save_stack_state` but is a general-purpose register access primitive.
- `compile_addr` (674-678): Gets the address of a label. Used by exception handling to get rescue label addresses, but is a general-purpose primitive (analogous to how Proc stores function addresses, as the existing comment notes).

These 6 methods stay in compiler.rb. They may be candidates for a future `compile_primitives.rb` extraction, but lumping them into `compile_rescue.rb` would misrepresent their purpose.

**Existing compile_*.rb extraction files follow this exact pattern:**
- [compile_calls.rb](../../compile_calls.rb) (515 lines)
- [compile_class.rb](../../compile_class.rb) (469 lines)
- [compile_control.rb](../../compile_control.rb) (365 lines)
- [compile_arithmetic.rb](../../compile_arithmetic.rb) (230 lines)
- [compile_include.rb](../../compile_include.rb) (87 lines)
- [compile_comparisons.rb](../../compile_comparisons.rb) (43 lines)
- [compile_pragma.rb](../../compile_pragma.rb) (24 lines)

Each reopens `class Compiler` and adds methods. The extraction follows this proven pattern exactly.

## Infrastructure Cost

Zero. This is a file-level refactoring that moves existing methods into a new file using Ruby's open-class mechanism (`class Compiler ... end`). No API changes, no new dependencies, no build system changes. The only integration point is adding `require 'compile_rescue'` to [compiler.rb](../../compiler.rb) alongside the other `require 'compile_*'` statements at lines 17-23. Validation uses existing `make selftest`, `make selftest-c`, and `make spec`.

## Scope

**In scope:**
- Create [compile_rescue.rb](../../compile_rescue.rb) that reopens `class Compiler` with the 6 exception/rescue methods
- Move these methods from [compiler.rb](../../compiler.rb):
  - `compile_rescue` (line 423)
  - `compile_raise` (line 430)
  - `compile_unwind` (line 702)
  - `compile_begin_rescues` (line 962)
  - `build_rescue_conditional` (line 996)
  - `compile_begin_rescue` (line 1053)
- Add `require 'compile_rescue'` to [compiler.rb](../../compiler.rb) at line 23 (after `compile_control`)
- Validate with `make selftest`, `make selftest-c`, and `make spec`

**Out of scope:**
- Moving `compile_block`, `compile_preturn`, `compile_stackframe`, `compile_caller_stackframe`, `compile_stackpointer`, or `compile_addr` — these are not exception-specific (see Root Cause section)
- Extracting other method groups (case/when, assignment, vtable, low-level primitives) — those are future cleanup plans
- Refactoring the exception compilation logic itself — this is a pure move, no behavior changes
- Modifying any method signatures or call sites
- Touching any file other than compiler.rb and the new compile_rescue.rb

## Expected Payoff

- [compiler.rb](../../compiler.rb) shrinks from 1640 to ~1390 lines (~15% reduction), making the remaining code easier to navigate
- Exception/rescue compilation logic is isolated in one file, making it easier to understand, debug, and modify independently
- Follows the established compile_*.rb decomposition pattern, reducing the mental model needed to work with the compiler
- The extraction itself validates that the compiler handles this code organization pattern correctly during self-hosting (a subtle SELFHOST test)
- Establishes a clean extraction boundary based on semantic cohesion rather than proximity — future extractions (case/when, assignment, low-level primitives) can follow the same principle
- Advances the README.md goal: "General cleanup. The code has gotten messy. Decompose into simpler components."

## Proposed Approach

1. Create [compile_rescue.rb](../../compile_rescue.rb) with `class Compiler` and the 6 exception/rescue methods, preserving their exact current implementation (including associated comments) with no changes.
2. Remove the 6 methods from [compiler.rb](../../compiler.rb). Leave `compile_block`, `compile_preturn`, `compile_stackframe`, `compile_caller_stackframe`, `compile_stackpointer`, and `compile_addr` in place.
3. Add `require 'compile_rescue'` to [compiler.rb](../../compiler.rb) at line 23.
4. Run `make selftest` to verify the compiler still works.
5. Run `make selftest-c` to verify self-hosting still works (the self-compiled compiler must also handle the new file layout).
6. Run `make spec` to verify no spec regressions.

## Acceptance Criteria

- [ ] [compile_rescue.rb](../../compile_rescue.rb) exists and contains exactly the 6 exception/rescue methods: `compile_rescue`, `compile_raise`, `compile_unwind`, `compile_begin_rescues`, `build_rescue_conditional`, `compile_begin_rescue`
- [ ] [compile_rescue.rb](../../compile_rescue.rb) does NOT contain `compile_block`, `compile_preturn`, `compile_stackframe`, `compile_caller_stackframe`, `compile_stackpointer`, or `compile_addr`
- [ ] [compiler.rb](../../compiler.rb) no longer contains any of the 6 extracted methods (verified by grep)
- [ ] [compiler.rb](../../compiler.rb) still contains `compile_block`, `compile_preturn`, `compile_stackframe`, `compile_caller_stackframe`, `compile_stackpointer`, and `compile_addr`
- [ ] [compiler.rb](../../compiler.rb) contains `require 'compile_rescue'` alongside the other compile_* requires
- [ ] `make selftest` passes
- [ ] `make selftest-c` passes
- [ ] `make spec` passes

---
*Status: PROPOSAL - Awaiting approval*
