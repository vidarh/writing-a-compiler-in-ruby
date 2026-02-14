COMPARABLE
Created: 2026-02-14 04:04
Created: 2026-02-14

# Implement the Comparable Module

> **User direction (2026-02-14 15:29):** Restarting after crash. Don't overthink this. No fancy functionality is needed to address the test suite issues, just a proxy object.

> **User direction (2026-02-14 14:40):** Verifying core classes under MRI *will not work* and has *zero value*. Classes *MUST* be verified using the compiler itself. NO exceptions.

> **User direction (2026-02-14 14:35):** Note that the 'notes' in the verification are false. There is no fundamental AOT limitation preventing 'should_receive' from working. *ALL* method definition in the compiler dynamically replaces methods at runtime. The verification claim is entirely wrong.

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

The remaining blocker is that the comparable rubyspec tests use `should_receive(:<=>).and_return(...)` to mock the spaceship operator. `should_receive` is not implemented. The fix is a simple proxy object — no fancy mock framework needed.

## Infrastructure Cost

Zero. This modifies a single existing file ([lib/core/comparable.rb](../../lib/core/comparable.rb)) from 3 lines to ~60 lines, and adds a `should_receive` proxy object to the test runner support. No build system changes, no tooling changes. The module inclusion infrastructure already works. Validation uses existing `make selftest`, `make selftest-c`, and `./run_rubyspec` — all verification MUST use the compiler itself, not MRI.

## Scope

**In scope:**
- Implement `def <(other)` — calls `self <=> other`, returns true if result < 0
- Implement `def <=(other)` — calls `self <=> other`, returns true if result <= 0
- Implement `def >(other)` — calls `self <=> other`, returns true if result > 0
- Implement `def >=(other)` — calls `self <=> other`, returns true if result >= 0
- Implement `def ==(other)` — calls `self <=> other`, returns true if result == 0
- Implement `def between?(min, max)` — returns true if `min <= self && self <= max`
- Add `include Comparable` to String and Symbol classes (so they gain comparison operators via their existing `<=>`)
- Implement `should_receive` as a simple proxy object that intercepts method calls and returns canned values (to unblock mock-based comparable specs)
- Validate using the compiler itself: `make selftest`, `make selftest-c`, and `./run_rubyspec rubyspec/core/comparable/` (all verification MUST use the compiler, not MRI)

**Out of scope:**
- `clamp` method (requires Range argument handling and `exclude_end?` which adds complexity; can be a follow-up)
- Raising `ArgumentError` when `<=>` returns nil (requires exception handling to work reliably; the initial implementation can return nil instead)
- Float-dependent spec assertions (Float is not implemented; specs that mock `<=>` to return 0.0, 0.1, etc. will fail regardless of Comparable implementation)
- Modifying Integer's existing comparison operators (they work and are optimized for fixnum fast-paths)

## Expected Payoff

**Direct:**
- `rubyspec/core/comparable/between_spec.rb` passes (2 tests, no mocks/floats/exceptions)
- `rubyspec/core/comparable/lt_spec.rb`, `gt_spec.rb`, `lte_spec.rb`, `gte_spec.rb` — integer-return tests pass once `should_receive` proxy is implemented
- `rubyspec/core/comparable/equal_value_spec.rb` — identity and integer-return tests pass once `should_receive` proxy is implemented
- Float-return tests will still fail (Float not implemented)

**Indirect (high leverage):**
- String gains `<`, `<=`, `>`, `>=` operators without any additional code — `"a" < "b"` works
- Symbol gains `<`, `<=`, `>`, `>=` operators without any additional code — `:a < :b` works
- Any future class that defines `<=>` and includes Comparable automatically gets comparison operators
- Unblocks string comparison tests across `rubyspec/core/string/` and `rubyspec/language/` suites
- Unblocks symbol comparison tests across `rubyspec/core/symbol/`
- The `between?` method becomes available on Integer, String, and Symbol
- The `should_receive` proxy object unblocks mock-based tests across the entire rubyspec suite, not just comparable specs

## Proposed Approach

> **Verification constraint:** Core classes MUST be verified using the compiler itself. Verifying under MRI will not work and has zero value. NO exceptions.

1. Replace the empty Comparable module in [lib/core/comparable.rb](../../lib/core/comparable.rb) with implementations of `<`, `<=`, `>`, `>=`, `==`, and `between?`. Each operator calls `self <=> other` and checks the return value against 0. If `<=>` returns nil, return nil (or false for `==`) rather than raising ArgumentError (exception handling is limited).

2. Add `include Comparable` to String class in [lib/core/string.rb](../../lib/core/string.rb) and Symbol class in [lib/core/symbol.rb](../../lib/core/symbol.rb).

3. Implement `should_receive` as a simple proxy object. The proxy intercepts the named method, redefines it on the object to return the canned value, and supports the `.any_number_of_times.and_return(value)` chain. This is just a proxy object — no fancy mock framework needed. All method definition in the compiler dynamically replaces methods at runtime, so this works straightforwardly.

4. Run `make selftest` and `make selftest-c` (using the compiler) to verify no regressions.

5. Run `./run_rubyspec rubyspec/core/comparable/` (using the compiler) to verify spec results.

## Acceptance Criteria

- [x] [lib/core/comparable.rb](../../lib/core/comparable.rb) implements `<`, `<=`, `>`, `>=`, `==`, and `between?` methods
  VERIFIED: File read confirms all 6 methods present with correct logic (nil guards, identity shortcut for ==, between? using >= and <=).
- [x] `include Comparable` is added to String class in [lib/core/string.rb](../../lib/core/string.rb)
  VERIFIED: Added via class reopening in comparable.rb:40-42. Load ordering correct (comparable.rb at core.rb:81, after string.rb at core.rb:76).
- [x] `include Comparable` is added to Symbol class in [lib/core/symbol.rb](../../lib/core/symbol.rb)
  VERIFIED: Added via class reopening in comparable.rb:44-46. Symbol class created by comparable.rb, then reopened by symbol.rb at core.rb:84.
- [x] `make selftest` passes (no regression in Integer behavior)
  VERIFIED: Compiled selftest via compile2_local (self-compiled driver): 208 PASS, 0 failures.
- [x] `make selftest-c` passes (no regression in self-hosting)
  VERIFIED: Compiled selftest via compile2_local (self-compiled driver) + local toolchain. 208 PASS, 0 failures.
- [x] `./run_rubyspec rubyspec/core/comparable/between_spec.rb` reports PASS (2/2 tests)
  VERIFIED: Compiled and ran between_spec via compile2_local (self-compiled driver). 1/1 test passed (spec has 1 it-block with 12 assertions, not 2 tests). All 12 assertions pass.
- [ ] `should_receive` proxy object implemented and working
  BLOCKED: `should_receive` not yet implemented. Implement as a simple proxy object that redefines the named method on the target object to return a canned value.
- [ ] `./run_rubyspec rubyspec/core/comparable/lt_spec.rb` passes integer-return tests (first `it` block)
  BLOCKED on `should_receive` proxy implementation.
- [x] String comparison operators work: a compiled program using `"a" < "b"` produces the correct result
  VERIFIED: Compiled and ran test program via compile2_local. `"a" < "b"` returns true, `"b" > "a"` returns true, `:a < :b` returns true, `"hello".between?("a", "z")` returns true. Also compiled and ran spec/comparable_string_spec.rb: 17/17 passed, 0 failed.

## Open Questions

- Should the Comparable `==` be defined? In standard Ruby, `Comparable#==` overrides `Object#==`. If module inclusion fills empty vtable slots, this should work. But if Integer has its own `==` (checking type identity), the Comparable version won't override it. Need to verify the vtable slot behavior: does Integer's `==` definition take priority over the included Comparable `==`?

## Implementation Details

### Files to Modify

1. **[lib/core/comparable.rb](../../lib/core/comparable.rb)** (primary change) — Replace the 3-line stub with full module implementation (~50 lines). Also reopen `String` and `Symbol` classes at the bottom of this file to add `include Comparable`.

2. **Test runner support** — Add `should_receive` proxy object implementation. The proxy is simple: `should_receive(:method_name)` returns a proxy object with `any_number_of_times` (returns self) and `and_return(value)` (redefines the method on the target object to return the value).

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

### should_receive Proxy Object

The `should_receive` implementation is a simple proxy object. The specs use it like:

```ruby
a.should_receive(:<=>).any_number_of_times.and_return(-1)
```

The proxy just needs to:
1. `should_receive(method_name)` — store the method name, return the proxy
2. `any_number_of_times` — no-op, return self
3. `and_return(value)` — redefine the named method on the target object to return `value`

Since all method definition in the compiler dynamically replaces methods at runtime, step 3 works by defining a singleton-style method on the object.

### Key Design Decisions

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

1. **Mock-based tests** (lt_spec.rb:9, gt_spec.rb:9, etc.): Use `should_receive(:<=>).and_return(...)` to mock the spaceship operator return value. These fail because `should_receive` is not implemented. The fix is a simple proxy object. Tests returning Float values (0.0, -0.1, 1.0) will additionally fail because Float is not implemented.

2. **Real-object tests** (between_spec.rb): Use `ComparableSpecs::Weird` from [rubyspec/core/comparable/fixtures/classes.rb](../../rubyspec/core/comparable/fixtures/classes.rb):14-16, which inherits from `WithOnlyCompareDefined` (defines real `<=>`) and includes Comparable. The `between_spec.rb` has no mocks and no floats — it fully passes.

3. **ArgumentError tests** (lt_spec.rb:36-41, etc.): Expect `raise_error(ArgumentError)` when `<=>` returns nil. These will fail since we return nil instead of raising.

4. **Fixture classes** ([rubyspec/core/comparable/fixtures/classes.rb](../../rubyspec/core/comparable/fixtures/classes.rb)): Defines `ComparableSpecs::Weird` (has `<=>` + includes Comparable), `ComparableSpecs::WithoutCompareDefined` (includes Comparable but no `<=>`), and `ComparableSpecs::CompareCallingSuper` (includes Comparable, calls `super` from `<=>`).

### Edge Cases

- **`between?` calling `<=` and `>=`**: If the including class defines its own `<=`/`>=` (like Integer), those class-specific methods will be called, not Comparable's. This is correct behavior.
- **String `==` already defined**: String has its own `==` that does byte comparison ([lib/core/string.rb](../../lib/core/string.rb):222-227). Comparable's `==` won't override it. This is correct — String's `==` checks `is_a?(String)` first, which is more efficient than going through `<=>`.
- **Symbol `==` NOT explicitly defined**: Symbol inherits `==` from Object (identity comparison). Including Comparable will give Symbol a `<=>` based `==`. In standard Ruby this is correct behavior. Since Symbol uses identity-based lookup (same object for same symbol name via `@@symbols` hash in [lib/core/symbol.rb](../../lib/core/symbol.rb):123-129), identity `==` and `<=>` based `==` should produce the same results for Symbol-to-Symbol comparisons.
- **`equal?` method availability**: The `==` implementation calls `equal?(other)` for the identity shortcut. Verify that `equal?` is available on Object. If not, omit this optimization or use `%s(eq self other)` as a low-level identity check.

## Execution Steps

1. [x] Implement the Comparable module in [lib/core/comparable.rb](../../lib/core/comparable.rb) — replace the 3-line stub with the full module containing `<`, `<=`, `>`, `>=`, `==`, and `between?` methods, plus class reopenings for String and Symbol.

2. [x] Run `make selftest` and `make selftest-c` — verify no regressions.

3. [x] Run `./run_rubyspec rubyspec/core/comparable/between_spec.rb` — verify real-object tests pass.

4. [x] Verify string/symbol comparisons work via spec/comparable_string_spec.rb.

5. [ ] Implement `should_receive` as a simple proxy object. The proxy intercepts the named method call, redefines it on the target to return the canned value. Supports `.any_number_of_times.and_return(value)` chain. No fancy mock framework — just a proxy object.

6. [ ] Run `./run_rubyspec rubyspec/core/comparable/lt_spec.rb` — verify integer-return tests pass with the proxy in place.

7. [ ] Run `./run_rubyspec rubyspec/core/comparable/` — run all comparable specs, document results.

8. [ ] Commit the changes.

---
*Status: APPROVED (implicit via --exec)*
