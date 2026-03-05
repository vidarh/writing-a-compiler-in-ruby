HASHSTUB
Created: 2026-03-05

# Add Hash Method Stubs to Convert Crashes to Failures

[COMPLANG] Add stub methods to [lib/core/hash.rb](lib/core/hash.rb) for commonly-tested Hash methods that currently cause segfaults when called from rubyspec tests. Stubs raise `NotImplementedError` to convert crashes into actionable failures.

## Goal Reference

[COMPLANG](docs/goals/COMPLANG-compiler-advancement.md): Improving Hash method coverage directly advances spec compliance. Many rubyspec language tests use Hash literals and methods; missing methods cause crashes that obscure actual test results.

## Prior Plans

- No prior plans specifically target Hash method stub implementation.
- The [core-library-implementations.md](docs/exploration/core-library-implementations.md) exploration note identifies "Hash method stubs" as a quick-win opportunity: "Adding stubs that raise `NotImplementedError` would convert crashes to failures, producing diagnostic output."

## Root Cause

The compiler's Hash implementation in [lib/core/hash.rb](lib/core/hash.rb) has only ~25 methods (including internal/private methods), while standard Ruby Hash has 100+ methods. When rubyspec tests call missing Hash methods, the compiler typically segfaults rather than raising a `NoMethodError` because:

1. The method lookup fails to find the method in Hash's vtable
2. The fallback `method_missing` path may not handle the case correctly for core types
3. The resulting NULL pointer dereference causes a segfault

This crash behavior is less actionable than a clear `NotImplementedError` with a message identifying the missing method. Converting crashes to failures allows:
- The test runner to continue past the failure
- The failure output to identify exactly which method is missing
- Developers to prioritize which methods to fully implement based on rubyspec usage frequency

## Infrastructure Cost

**Low**. This plan only modifies [lib/core/hash.rb](lib/core/hash.rb), adding method definitions that raise `NotImplementedError`. No changes to:
- Build system (Makefile)
- Test infrastructure (run_rubyspec)
- Compiler core (parser, emitter, etc.)
- Other core library files

The only dependency is that `NotImplementedError` must be defined (it is, in [lib/core/exception.rb](lib/core/exception.rb)).

## Scope

**In scope:**

1. Identify the ~20 most commonly-tested Hash methods that are missing from [lib/core/hash.rb](lib/core/hash.rb) by examining rubyspec language tests and core/hash specs (if available)

2. Add stub implementations for each missing method that:
   - Accept the correct parameters (matching Ruby's signature)
   - Raise `NotImplementedError` with a descriptive message including the method name
   - Include a comment indicating this is a stub for rubyspec compatibility

3. Priority methods to stub (based on exploration notes and common Ruby usage):
   - `each_pair` (alias for `each`)
   - `each_key` (iterate keys only)
   - `each_value` (iterate values only)
   - `select` (filter by key-value pair)
   - `reject` (inverse filter)
   - `fetch` (key lookup with default/block)
   - `store` (alias for `[]=`)
   - `update` (alias for `merge!`)
   - `has_value?` / `value?` (check if value exists)
   - `key` (reverse lookup: find key for value)
   - `invert` (swap keys and values)
   - `compact` / `compact!` (remove nil values)
   - `transform_values` / `transform_values!` (map values)
   - `slice` (extract subset by keys)
   - `except` (exclude keys)

4. Run `make selftest` and `make selftest-c` to ensure no regressions

5. Run `./run_rubyspec rubyspec/language/` to verify that some previously-crashing tests now produce `NotImplementedError` failures instead of segfaults

**Out of scope:**

- Full implementation of the stubbed methods (that would be follow-up plans)
- Adding all 100+ missing Hash methods (focus on the ~20 most commonly tested)
- Modifying the method lookup system to automatically raise instead of segfault
- Changes to other core types (Array, String, etc.)

## Expected Payoff

**Immediate:**
- Convert segfaults to actionable `NotImplementedError` failures in rubyspec tests
- Identify exactly which Hash methods are most needed by rubyspec
- Provide foundation for incremental Hash method implementation

**Downstream (COMPLANG):**
- Enable more rubyspec tests to run to completion (even if failing)
- Better metrics: distinguish "missing method" failures from actual semantic failures
- Prioritized roadmap: implement most-tested methods first

**Documentation:**
- Updated [lib/core/hash.rb](lib/core/hash.rb) with clear stub markers
- Comments indicate which methods are stubs vs fully implemented

## Proposed Approach

1. **Analyze rubyspec usage** (optional, can use priority list from exploration notes):
   ```bash
   # If rubyspec submodule is populated:
   grep -r "\.each_pair\|\.each_key\|\.each_value\|\.select\|\.reject\|\.fetch\|\.store\|\.update\|\.has_value\|\.value\?\|\.key\|\.invert\|\.compact\|\.transform_values\|\.slice\|\.except" rubyspec/language/ | wc -l
   ```

2. **Add stubs to hash.rb**: Append stub methods at the end of the Hash class, after the fully implemented methods. Each stub follows this pattern:
   ```ruby
   # STUB: Converts crash to NotImplementedError for rubyspec compatibility
   def each_pair(&block)
     raise NotImplementedError, "Hash#each_pair is a stub"
   end
   ```

3. **Add aliases separately** for methods that are aliases in Ruby:
   ```ruby
   alias each_pair each  # If we want each_pair to work via each
   # OR as stub:
   alias store []=
   alias update merge
   ```

4. **Validate**: Run `make selftest && make selftest-c` to ensure no regressions.

## Acceptance Criteria

- [ ] [lib/core/hash.rb](lib/core/hash.rb) contains stub implementations for at least 15 of the priority methods listed in the Scope section
- [ ] Each stub method raises `NotImplementedError` with a message identifying the method name
- [ ] `make selftest` passes (no regressions in self-hosted compilation)
- [ ] `make selftest-c` passes (no regressions in self-compiled compiler)
- [ ] At least one previously-crashing rubyspec test now produces a `NotImplementedError` failure instead of a segfault (documented in log)

## Open Questions

- Should we implement some methods as aliases to existing methods (e.g., `each_pair` → `each`) or as stubs? `each` already yields key-value pairs, so `each_pair` could be an alias.
- Should `store` be an alias for `[]=` (which is implemented) or a stub? It's a pure alias in Ruby.
- How many methods should be fully implemented vs stubbed in this plan? The scope suggests ~15-20 stubs, but which ones are most critical?

## Notes

- The `NotImplementedError` exception class is defined in [lib/core/exception.rb](lib/core/exception.rb) as part of the standard exception hierarchy.
- Some methods like `each_pair`, `store`, and `update` are aliases in standard Ruby and could be implemented as such rather than stubs.
- The exploration notes suggest this is a "quick-win" because stubs are low-effort but high-value for diagnostics.

---
*Status: PROPOSAL - Awaiting approval*
