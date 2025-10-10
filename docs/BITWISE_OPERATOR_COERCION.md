# Bitwise Operator Coercion Investigation

## Issue
The `bit_and_spec.rb` test is segfaulting because bitwise operators (`&`, `|`, `^`, `<<`, `>>`) don't implement proper Ruby coercion.

## Current State
The operators currently:
1. Check if `other.is_a?(Integer)`
2. If yes, call `__get_raw` and perform the operation
3. If no, print error to STDERR and return `nil`

This approach does NOT match Ruby semantics and causes spec failures.

## Ruby Coercion Protocol
When a binary operator receives an object it can't handle:

1. Call `other.coerce(self)` which should return `[converted_self, converted_other]`
2. Perform the operation on the converted values
3. If coerce is not defined or fails, raise TypeError

Example from spec:
```ruby
obj.should_receive(:coerce).with(6).and_return([6, 3])
(6 & obj).should == 2
```

This means: `6 & obj` → `obj.coerce(6)` returns `[6, 3]` → perform `6 & 3` → result is `2`

## Implementation Plan
For each bitwise operator:
1. Check if `other.is_a?(Integer)`
2. If yes, use fast path with `__get_raw`
3. If no, try coercion:
   - Call `other.coerce(self)`
   - Extract the two values from the array
   - Recursively call the operator with the coerced values

## Bootstrap Constraints
- Can't use exceptions (`begin/rescue`)
- Can't use `unless`
- Can't use `return` with s-expressions
- Need to handle missing methods gracefully

## Current Status
- ✅ Implemented coercion in `&` operator
- ✅ Simple test case with real coerce method works
- ❌ RubySpec test STILL segfaults - but reverting coercion code does NOT fix it
  - The segfault is PRE-EXISTING, not caused by coercion implementation
  - Crash at address `0xfffffffd` (trying to call fixnum 1 as function)
  - This matches the lambda/proc/closure bug identified in docs/TODO.md
  - Backtrace shows crash in lambda call chain

## Root Cause Analysis
The spec segfaults because of unrelated lambda/proc issues, NOT because of missing coercion.
The crash happens during test framework setup/execution, before the coercion test even runs.

From TODO.md summary:
- Crashes at small odd addresses (0x3, 0x5, 0xb, 0xfffffffd) indicate fixnums being called as functions
- This is a closure/proc issue where fixnum values end up in function pointer positions
- Affects tests that use lambdas (`->`)

## Next Steps - REVISED
The coercion implementation is CORRECT. The spec failure is due to deeper lambda/proc bugs.

**CRITICAL FINDING**: Even the simplest lambda `-> { puts "test" }` causes a segfault BEFORE ANY USER CODE RUNS. The crash happens during program initialization. This means:

1. The `bit_and_spec.rb` failure is NOT fixable by improving the `&` operator
2. The spec uses `-> { ... }` syntax for testing exception raising
3. Lambda support is completely broken - crashes immediately on program start
4. This is a fundamental compiler bug in lambda/proc implementation

**Blocking Issue**: Cannot fix `bit_and_spec.rb` without first fixing lambda initialization.

The test file `test_simple_lambda_crash.rb` and `test_lambda_debug.rb` demonstrate the issue.

## Related Files
- `lib/core/fixnum.rb` - Integer (Fixnum) implementation
- `rubyspec/core/integer/bit_and_spec.rb` - Test that's failing
- `rubyspec_temp_bit_and_spec.rb` - Preprocessed version in repo root
- `rubyspec_helper.rb` - Mock framework (currently just stubs)
