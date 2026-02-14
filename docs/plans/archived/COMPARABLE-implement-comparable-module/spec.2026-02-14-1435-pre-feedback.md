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

- [x] [lib/core/comparable.rb](../../lib/core/comparable.rb) implements `<`, `<=`, `>`, `>=`, `==`, and `between?` methods
  VERIFIED: File read confirms all 6 methods present with correct logic (nil guards, identity shortcut for ==, between? using >= and <=).
- [x] `include Comparable` is added to String class in [lib/core/string.rb](../../lib/core/string.rb)
  VERIFIED: Added via class reopening in comparable.rb:40-42. Load ordering correct (comparable.rb at core.rb:81, after string.rb at core.rb:76).
- [x] `include Comparable` is added to Symbol class in [lib/core/symbol.rb](../../lib/core/symbol.rb)
  VERIFIED: Added via class reopening in comparable.rb:44-46. Symbol class created by comparable.rb, then reopened by symbol.rb at core.rb:84.
- [x] `make selftest` passes (no regression in Integer behavior)
  VERIFIED: Compiled selftest via MRI driver.rb + local toolchain. 211 PASS, 0 failures. Also verified via compile2_local (self-compiled driver): 208 PASS, 0 failures.
- [x] `make selftest-c` passes (no regression in self-hosting)
  VERIFIED: Compiled selftest via compile2_local (self-compiled driver) + local toolchain. 208 PASS, 0 failures.
- [x] `./run_rubyspec rubyspec/core/comparable/between_spec.rb` reports PASS (2/2 tests)
  VERIFIED: Compiled and ran between_spec manually (MRI driver.rb + local toolchain). 1/1 test passed (spec has 1 it-block with 12 assertions, not 2 tests). All 12 assertions pass.
- [ ] `./run_rubyspec rubyspec/core/comparable/lt_spec.rb` runs without crash and passes at least the first `it` block (integer-return test)
  FAIL: Compiles and runs without crash (no segfault). However, the first `it` block uses `should_receive(:<=>)` on a real ComparableSpecs::Weird object, which requires runtime method replacement incompatible with AOT compilation. All 3 `it` blocks fail with "undefined method 'should_receive'". The spec runs but no `it` block passes.
- [x] String comparison operators work: a compiled program using `"a" < "b"` produces the correct result
  VERIFIED: Compiled and ran test program via compile2_local. `"a" < "b"` returns true, `"b" > "a"` returns true, `:a < :b` returns true, `"hello".between?("a", "z")` returns true. Also compiled and ran spec/comparable_string_spec.rb: 17/17 passed, 0 failed.

## Open Questions

- Should the Comparable `==` be defined? In standard Ruby, `Comparable#==` overrides `Object#==`. If module inclusion fills empty vtable slots, this should work. But if Integer has its own `==` (checking type identity), the Comparable version won't override it. Need to verify the vtable slot behavior: does Integer's `==` definition take priority over the included Comparable `==`?

## Implementation Details

### Files to Modify

1. **[lib/core/comparable.rb](../../lib/core/comparable.rb)** (primary change) — Replace the 3-line stub with full module implementation (~50 lines). Also reopen `String` and `Symbol` classes at the bottom of this file to add `include Comparable`.

### Files NOT Modified

- **[lib/core/string.rb](../../lib/core/string.rb)** — Cannot add `include Comparable` here because string.rb is loaded at [lib/core/core.rb](../../lib/core/core.rb):76, BEFORE comparable.rb at line 81. The Comparable module doesn't exist yet when String is being defined. Instead, we reopen String at the bottom of comparable.rb.
- **[lib/core/symbol.rb](../../lib/core/symbol.rb)** — Although symbol.rb is loaded at [lib/core/core.rb](../../lib/core/core.rb):84 (after comparable.rb at line 81), we handle the `include Comparable` from within comparable.rb for consistency and co-location of all Comparable-related includes.
- **[lib/core/integer.rb](../../lib/core/integer.rb)** — Integer already defines its own `<`, `<=`, `>`, `>=`, `==` at lines 3536-3569. The `__include_module` runtime function ([lib/core/class.rb](../../lib/core/class.rb):94-111) only copies vtable slots that are still uninitialized, so Integer's operators won't be overwritten.
- **[lib/core/core.rb](../../lib/core/core.rb)** — No load order changes needed. comparable.rb (line 81) is already loaded after string.rb (line 76) and before integer.rb (line 82), which is the correct ordering for reopening String.

### Implementation Pattern

The Comparable methods follow a simple pattern — call `self <=> other`, then compare the return value against 0:

```ruby
module Comparable
  def <(other)
    cmp = (self <=> other)
    return nil if cmp.nil?
    cmp < 0
  end
  # ... similar for <=, >, >=

  def ==(other)
    return true if equal?(other)
    cmp = (self <=> other)
    return false if cmp.nil?
    cmp == 0
  end

  def between?(min, max)
    self >= min && self <= max
  end
end

# Reopen classes to include Comparable (loaded after string.rb, before symbol.rb in core.rb)
class String
  include Comparable
end

class Symbol
  include Comparable
end
```

Key design decisions:
- **nil handling**: When `<=>` returns nil, return `nil` (or `false` for `==`) instead of raising ArgumentError. Exception handling is limited in this compiler, and the plan explicitly puts ArgumentError out of scope.
- **No type coercion**: The comparison result is checked as a simple integer comparison (`cmp < 0`, `cmp > 0`, `cmp == 0`). This works because the compiler's Integer `<` and `>` operators handle fixnum comparisons.
- **`==` identity shortcut**: `equal?(other)` check returns `true` immediately for same object, avoiding the `<=>` call. This matches MRI Ruby's Comparable#== behavior.
- **`between?` method**: Uses `self >= min && self <= max`, which delegates to the Comparable `>=` and `<=` methods (or the class's own if defined).
- **Reopening classes**: String and Symbol are reopened at the bottom of comparable.rb with just `include Comparable`. This follows the same pattern used by [lib/core/class_ext.rb](../../lib/core/class_ext.rb) and [lib/core/hash_ext.rb](../../lib/core/hash_ext.rb), which reopen classes to add functionality after dependencies are loaded.

### Vtable Slot Behavior (Answering Open Question)

Confirmed by reading [lib/core/class.rb](../../lib/core/class.rb):94-111: `__include_module` iterates vtable slots and only copies from the module if `(eq (index klass i) (index __base_vtable i))` — i.e., the class slot is still uninitialized. This means:
- Integer's `==` at [lib/core/integer.rb](../../lib/core/integer.rb):3558 takes priority over Comparable's `==`.
- String's `==` at [lib/core/string.rb](../../lib/core/string.rb):222 takes priority over Comparable's `==`.
- String does NOT define `<`, `<=`, `>`, `>=`, so those slots WILL be filled by Comparable's versions.
- Symbol does NOT define `<`, `<=`, `>`, `>=`, `==`, so ALL those slots will be filled by Comparable.

### Spec Expectations

The rubyspec comparable specs ([rubyspec/core/comparable/](../../rubyspec/core/comparable/)) use several patterns:

1. **Mock-based tests** (lt_spec.rb:9, gt_spec.rb:9, etc.): Use `should_receive(:<=>).and_return(...)` to mock the spaceship operator return value. Tests returning Float values (0.0, -0.1, 1.0) will fail because Float is not implemented.

2. **Real-object tests** (between_spec.rb): Use `ComparableSpecs::Weird` from [rubyspec/core/comparable/fixtures/classes.rb](../../rubyspec/core/comparable/fixtures/classes.rb):14-16, which inherits from `WithOnlyCompareDefined` (defines real `<=>`) and includes Comparable. The `between_spec.rb` has no mocks and no floats — it should fully pass.

3. **ArgumentError tests** (lt_spec.rb:36-41, etc.): Expect `raise_error(ArgumentError)` when `<=>` returns nil. These will fail since we return nil instead of raising.

4. **Fixture classes** ([rubyspec/core/comparable/fixtures/classes.rb](../../rubyspec/core/comparable/fixtures/classes.rb)): Defines `ComparableSpecs::Weird` (has `<=>` + includes Comparable), `ComparableSpecs::WithoutCompareDefined` (includes Comparable but no `<=>`), and `ComparableSpecs::CompareCallingSuper` (includes Comparable, calls `super` from `<=>`).

### Edge Cases

- **`between?` calling `<=` and `>=`**: If the including class defines its own `<=`/`>=` (like Integer), those class-specific methods will be called, not Comparable's. This is correct behavior.
- **String `==` already defined**: String has its own `==` that does byte comparison ([lib/core/string.rb](../../lib/core/string.rb):222-227). Comparable's `==` won't override it. This is correct — String's `==` checks `is_a?(String)` first, which is more efficient than going through `<=>`.
- **Symbol `==` NOT explicitly defined**: Symbol inherits `==` from Object (identity comparison). Including Comparable will give Symbol a `<=>` based `==`. In standard Ruby this is correct behavior. Since Symbol uses identity-based lookup (same object for same symbol name via `@@symbols` hash in [lib/core/symbol.rb](../../lib/core/symbol.rb):123-129), identity `==` and `<=>` based `==` should produce the same results for Symbol-to-Symbol comparisons.
- **`equal?` method availability**: The `==` implementation calls `equal?(other)` for the identity shortcut. Verify that `equal?` is available on Object. If not, omit this optimization or use `%s(eq self other)` as a low-level identity check.

## Execution Steps

1. [ ] Implement the Comparable module in [lib/core/comparable.rb](../../lib/core/comparable.rb) — replace the 3-line stub with the full module containing `<`, `<=`, `>`, `>=`, `==`, and `between?` methods. Each operator calls `self <=> other`, checks for nil return, and compares result against 0. Add reopened `String` and `Symbol` classes at the bottom with `include Comparable`.

2. [ ] Run `make selftest` inside Docker (`make cli` then `make selftest`) — verify Integer comparison operators still work correctly and no regressions from the Comparable module inclusion. Integer's own operators should take priority over Comparable's.

3. [ ] Run `make selftest-c` inside Docker — verify the self-compiled compiler still works. This confirms the Comparable module implementation doesn't break the bootstrap chain.

4. [ ] Run `./run_rubyspec rubyspec/core/comparable/between_spec.rb` — this spec uses real objects (no mocks, no floats) and should fully pass. Verify 2/2 tests pass.

5. [ ] Run `./run_rubyspec rubyspec/core/comparable/` — run all comparable specs to see overall results. Document which tests pass and which fail (expected failures: Float-dependent tests, ArgumentError tests).

6. [ ] Create a string comparison validation spec in `spec/` — write a minimal mspec test that verifies `"a" < "b"`, `"z" > "a"`, `"hello" >= "hello"`, `"a" <= "b"`, and `"a".between?("a", "z")` all produce correct results. Run with `./run_rubyspec spec/<filename>`.

7. [ ] Commit the changes with a descriptive message. Files to commit: [lib/core/comparable.rb](../../lib/core/comparable.rb) and the new spec file.

---
*Status: APPROVED (implicit via --exec)*