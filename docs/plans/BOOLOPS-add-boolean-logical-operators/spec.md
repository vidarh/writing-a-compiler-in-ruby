BOOLOPS
Created: 2026-02-11

# Add Missing Boolean Logical Operators (&, |, ^)

[FUNCTIONALITY] Fix missing `&`, `|`, `^` methods on NilClass and missing `__true?` on TrueClass/Object, which cause failures and segfaults across 6+ core spec files.

## Goal Reference

[COMPLANG](../../goals/COMPLANG-compiler-advancement.md)

## Root Cause

Ruby defines `&`, `|`, `^` as methods on `TrueClass`, `FalseClass`, and `NilClass` for boolean logic (distinct from short-circuit `&&`/`||`). The compiler's implementations in [lib/core/true.rb](../../../lib/core/true.rb) and [lib/core/false.rb](../../../lib/core/false.rb) use a private helper `__true?` to test the truthiness of the `other` argument. However:

1. **`__true?` is only defined on `FalseClass` and `NilClass`** (returning falsey via `%s(sexp 0)`). It is NOT defined on `TrueClass` or `Object`. So `true & true` calls `true.__true?` which raises "undefined method '__true?' for true", and `false | "hello"` calls `"hello".__true?` which also fails.

2. **`NilClass` has no `&`, `|`, `^` methods at all.** [lib/core/nil.rb](../../../lib/core/nil.rb) defines `__true?` but never defines the operators themselves, so `nil & x` raises "undefined method '&' for nil".

3. **`FalseClass#|` and `FalseClass#^` segfault** when called with certain arguments, likely because the missing `__true?` method dispatch corrupts the stack.

Confirmed by running specs live:
- `./run_rubyspec rubyspec/core/nil/and_spec.rb` -> `undefined method '&' for nil`
- `./run_rubyspec rubyspec/core/true/and_spec.rb` -> `undefined method '__true?' for true`
- `./run_rubyspec rubyspec/core/false/or_spec.rb` -> Segfault (exit 139)

## Infrastructure Cost

Zero. This adds methods to three existing files in [lib/core/](../../../lib/core/). No new files, no build system changes, no tooling.

## Scope

**In scope:**
- Add `def __true?` to `TrueClass` in [lib/core/true.rb](../../../lib/core/true.rb) returning truthy
- Add `def __true?` to `Object` in [lib/core/object.rb](../../../lib/core/object.rb) returning truthy (default: all objects are truthy)
- Add `def &`, `def |`, `def ^` to `NilClass` in [lib/core/nil.rb](../../../lib/core/nil.rb) using the same `__true?` pattern
- Validate with `make selftest`, `make selftest-c`, and the 6 affected spec files

**Out of scope:**
- Fixing `NilClass.allocate`/`.new` spec failures (different issue: class instantiation guards)
- Fixing `to_s` encoding-related failures
- Adding `&`/`|` to `Array` (commented out in array.rb, different feature)

## Expected Payoff

- 6 spec files flip from FAIL/CRASH to PASS across core/nil/, core/true/, core/false/ (and_spec, or_spec, xor_spec)
- core/nil pass rate improves from 7/18 to 10/18 (39% -> 56%)
- core/true pass rate improves from 4/9 to 7/9 (44% -> 78%)
- core/false pass rate improves from 4/9 to 6/9 (44% -> 67%)
- Approximately 10 additional individual tests pass (6 tests currently showing 0 pass due to missing methods)
- The `__true?` method on Object enables all future uses of boolean operators with arbitrary objects

## Proposed Approach

1. Add `def __true?; true; end` to `Object` in [lib/core/object.rb](../../../lib/core/object.rb) (base case: everything is truthy)
2. Add `def __true?; true; end` to `TrueClass` in [lib/core/true.rb](../../../lib/core/true.rb)
3. Add three methods to `NilClass` in [lib/core/nil.rb](../../../lib/core/nil.rb): `def &(other); false; end`, `def |(other); other.__true?; end`, `def ^(other); other.__true?; end`
4. Validate with selftest/selftest-c and all 6 target specs

## Acceptance Criteria

- [ ] `./run_rubyspec rubyspec/core/nil/and_spec.rb` reports PASS (no "undefined method" errors)
- [ ] `./run_rubyspec rubyspec/core/true/and_spec.rb` reports PASS (no "__true?" errors)
- [ ] `./run_rubyspec rubyspec/core/false/or_spec.rb` reports PASS (no segfault)
- [ ] `make selftest` and `make selftest-c` both pass

## Open Questions

- Should `Object#__true?` use `true` (a Ruby-level return) or `%s(sexp 1)` (a low-level truthy value matching the `%s(sexp 0)` pattern used in FalseClass/NilClass)? The answer depends on whether the callers expect a Ruby boolean or a raw tagged value.

---
*Status: PROPOSAL - Awaiting approval*
