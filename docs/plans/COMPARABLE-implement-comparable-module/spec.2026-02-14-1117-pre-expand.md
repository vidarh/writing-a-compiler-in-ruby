COMPARABLE
Created: 2026-02-14 04:04
Created: 2026-02-14

# Implement the Comparable Module

[COMPLANG] Implement the 6 core methods in the Comparable module (`<`, `<=`, `==`, `>`, `>=`, `between?`) so that any class defining `<=>` and including `Comparable` gets comparison operators automatically. This enables 7 rubyspec/core/comparable/ spec files and gives String and Symbol free comparison operators.

## Goal Reference

[COMPLANG](../../goals/COMPLANG-compiler-advancement.md)

## Root Cause

[lib/core/comparable.rb](../../lib/core/comparable.rb) is a 3-line empty stub:

```ruby
# FIXME: Stub - Comparable module not fully implemented
module Comparable
end
```

Despite this, [lib/core/integer.rb](../../lib/core/integer.rb):13 already does `include Comparable`, meaning Integer is paying the cost of including a module that provides nothing. Integer works anyway because it defines its own `<`, `<=`, `>`, `>=` directly (at lines 3536-3555), but this means the `include Comparable` is dead code.

More importantly, String ([lib/core/string.rb](../../lib/core/string.rb):306) and Symbol ([lib/core/symbol.rb](../../lib/core/symbol.rb):41) both define `<=>` but do NOT define `<`, `<=`, `>`, `>=`. In standard Ruby, these operators come from `include Comparable`. Without a working Comparable module, String and Symbol lack comparison operators entirely — `"a" < "b"` raises "undefined method '<' for String". This causes cascading failures across the rubyspec suite wherever string or symbol comparisons are used.

Module inclusion has been confirmed to work in this compiler (see [spec/include_simple_test_spec.rb](../../spec/include_simple_test_spec.rb)), so the only missing piece is implementing the methods in the Comparable module itself.

## Infrastructure Cost

Zero. This modifies a single existing file ([lib/core/comparable.rb](../../lib/core/comparable.rb)) from 3 lines to ~60 lines. No new files, no build system changes, no tooling changes. The module inclusion infrastructure already works. Validation uses existing `make selftest`, `make selftest-c`, and `./run_rubyspec`.

## Scope

**In scope:**
- Implement `def <(other)` — calls `self <=> other`, returns true if result < 0
- Implement `def <=(other)` — calls `self <=> other`, returns true if result <= 0
- Implement `def >(other)` — calls `self <=> other`, returns true if result > 0
- Implement `def >=(other)` — calls `self <=> other`, returns true if result >= 0
- Implement `def ==(other)` — calls `self <=> other`, returns true if result == 0
- Implement `def between?(min, max)` — returns true if `min <= self && self <= max`
- Add `include Comparable` to String and Symbol classes (so they gain comparison operators via their existing `<=>`)
- Validate with `make selftest`, `make selftest-c`, and `./run_rubyspec rubyspec/core/comparable/`

**Out of scope:**
- `clamp` method (requires Range argument handling and `exclude_end?` which adds complexity; can be a follow-up)
- Raising `ArgumentError` when `<=>` returns nil (requires exception handling to work reliably; the initial implementation can return nil instead)
- Float-dependent spec assertions (Float is not implemented; specs that mock `<=>` to return 0.0, 0.1, etc. will fail regardless of Comparable implementation)
- Modifying Integer's existing comparison operators (they work and are optimized for fixnum fast-paths)

## Expected Payoff

**Direct:**
- `rubyspec/core/comparable/between_spec.rb` passes (2 tests, no mocks/floats/exceptions)
- `rubyspec/core/comparable/lt_spec.rb`, `gt_spec.rb`, `lte_spec.rb`, `gte_spec.rb` — integer-return tests pass (~4-8 individual tests)
- `rubyspec/core/comparable/equal_value_spec.rb` — identity and integer-return tests pass (~4-6 tests)
- Estimated 13-17 individual test passes across 7 spec files

**Indirect (high leverage):**
- String gains `<`, `<=`, `>`, `>=` operators without any additional code — `"a" < "b"` works
- Symbol gains `<`, `<=`, `>`, `>=` operators without any additional code — `:a < :b` works
- Any future class that defines `<=>` and includes Comparable automatically gets comparison operators
- Unblocks string comparison tests across `rubyspec/core/string/` and `rubyspec/language/` suites
- Unblocks symbol comparison tests across `rubyspec/core/symbol/`
- The `between?` method becomes available on Integer, String, and Symbol

## Proposed Approach

1. Replace the empty Comparable module in [lib/core/comparable.rb](../../lib/core/comparable.rb) with implementations of `<`, `<=`, `>`, `>=`, `==`, and `between?`. Each operator calls `self <=> other` and checks the return value against 0. If `<=>` returns nil, return nil (or false for `==`) rather than raising ArgumentError (exception handling is limited).

2. Add `include Comparable` to String class in [lib/core/string.rb](../../lib/core/string.rb) and Symbol class in [lib/core/symbol.rb](../../lib/core/symbol.rb).

3. Run `make selftest` and `make selftest-c` to verify no regressions. Integer defines its own operators that take precedence over Comparable's (since `include` only fills unoccupied vtable slots), so Integer behavior should be unchanged.

4. Run `./run_rubyspec rubyspec/core/comparable/` to verify spec results.

5. Spot-check string comparisons work: run relevant string specs or a quick manual test.

## Acceptance Criteria

- [ ] [lib/core/comparable.rb](../../lib/core/comparable.rb) implements `<`, `<=`, `>`, `>=`, `==`, and `between?` methods
- [ ] `include Comparable` is added to String class in [lib/core/string.rb](../../lib/core/string.rb)
- [ ] `include Comparable` is added to Symbol class in [lib/core/symbol.rb](../../lib/core/symbol.rb)
- [ ] `make selftest` passes (no regression in Integer behavior)
- [ ] `make selftest-c` passes (no regression in self-hosting)
- [ ] `./run_rubyspec rubyspec/core/comparable/between_spec.rb` reports PASS (2/2 tests)
- [ ] `./run_rubyspec rubyspec/core/comparable/lt_spec.rb` runs without crash and passes at least the first `it` block (integer-return test)
- [ ] String comparison operators work: a compiled program using `"a" < "b"` produces the correct result

## Open Questions

- Should the Comparable `==` be defined? In standard Ruby, `Comparable#==` overrides `Object#==`. If module inclusion fills empty vtable slots, this should work. But if Integer has its own `==` (checking type identity), the Comparable version won't override it. Need to verify the vtable slot behavior: does Integer's `==` definition take priority over the included Comparable `==`?

---
*Status: APPROVED (implicit via --exec)*