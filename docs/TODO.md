# Ruby Compiler TODO

**Purpose**: Task list for improving rubyspec integer test pass rate.
**Format**: One-line tasks. Details in referenced docs.
**Rule**: Only work on tasks that improve rubyspec test results.

**IMPORTANT**: Validate tasks before starting - check if already completed.

**Current Status**: 22/67 specs passing (33%), 311/609 tests passing (51%)
**Goal**: Maximize test pass rate by fixing root causes

**For details**: See [RUBYSPEC_STATUS.md](RUBYSPEC_STATUS.md)
**For ongoing work**: See [WORK_STATUS.md](WORK_STATUS.md) (journaling space)
**For debugging**: See [DEBUGGING_GUIDE.md](DEBUGGING_GUIDE.md)

---

## QUICK WINS: Simple Fixes for Maximum Test Improvements

### 1. Fix Integer#bit_length Off-by-One Error (EASIEST - ~5 min) → +4 specs PASS

**Current Status**: bit_length_spec P:0 F:4 - ALL failures are systematic off-by-one errors
- Expected 1, got 0
- Expected 0, got 1
- Expected 2, got 3
- Expected 13, got 12 / Expected 12, got 13

**Fix**: Investigate `Integer#bit_length` implementation - likely returning `value - 1` or `value + 1` instead of correct value.

**Impact**: bit_length_spec: P:0 F:4 → P:4 F:0 ✓ **FULL PASS (+1 spec)**

**Files**: `lib/core/integer.rb` (search for `def bit_length`)
**Estimated effort**: 5-10 minutes

---

### 2. Add Float TypeError to Bitwise Operators (~15 min) → +3-6 tests

**Current Status**: Bitwise operators don't raise TypeError when passed Float
- bit_and_spec: P:11 F:2 - 2 failures are missing TypeError for Float
- bit_or_spec: P:7 F:5 - 3 failures are missing TypeError for Float
- bit_xor_spec: P:6 F:7 - some failures are missing TypeError for Float

**Fix**: Add type check at start of Integer#&, Integer#|, Integer#^:
```ruby
def & other
  raise TypeError.new("can't convert Float into Integer") if other.is_a?(Float)
  # ... rest of implementation
end
```

**Impact**:
- bit_and_spec: P:11 F:2 → P:13 F:0 ✓ **FULL PASS (+1 spec, +2 tests)**
- bit_or_spec: P:7 F:5 → P:10 F:2 (+3 tests)
- bit_xor_spec: P:6 F:7 → likely +1-2 tests

**Files**: `lib/core/integer.rb` (Integer#&, Integer#|, Integer#^)
**Estimated effort**: 15 minutes

---

### 3. Fix Integer#=== (case_compare) (~30 min) → +1 spec PASS

**Current Status**: case_compare_spec P:1 F:4 - all failures related to === not working correctly
- "Expected true but got false" when comparing self == other
- Calls 'other == self' if argument not Integer - but doesn't work

**Investigation Needed**:
- Check if Integer#=== is implemented or inherited from Object
- Ruby semantics: Integer#===(other) should return true if other has same value
- Should call other == self if other is not an Integer

**Impact**: case_compare_spec: P:1 F:4 → P:5 F:0 ✓ **FULL PASS (+1 spec, +4 tests)**

**Files**: `lib/core/integer.rb` or `lib/core/object.rb`
**Estimated effort**: 30 minutes

---

### 4. Add ArgumentError to Comparison Operators (~20 min) → +8-12 tests, +2-4 specs PASS

**Current Status**: Comparison operators don't raise ArgumentError for incomparable types
- gt_spec (>): P:0 F:5 - 2 failures are missing ArgumentError
- gte_spec (>=): P:0 F:5 - 2 failures are missing ArgumentError
- lt_spec (<): P:1 F:4 - likely 2 failures are missing ArgumentError
- lte_spec (<=): P:3 F:4 - 2 failures are missing ArgumentError

**Fix**: Add type check to Integer#<=> (spaceship operator):
```ruby
def <=> other
  # Handle Integer comparison...
  # If other is not comparable:
  raise ArgumentError.new("comparison of Integer with #{other.class} failed")
end
```

**Note**: Fixing <=> will propagate to <, >, <=, >= if they use <=> internally.

**Impact**:
- gt_spec: P:0 F:5 → likely P:5 F:0 ✓ **FULL PASS (+1 spec)**
- gte_spec: P:0 F:5 → likely P:5 F:0 ✓ **FULL PASS (+1 spec)**
- lt_spec: P:1 F:4 → likely P:5 F:0 ✓ **FULL PASS (+1 spec)**
- lte_spec: P:3 F:4 → likely P:7 F:0 ✓ **FULL PASS (+1 spec)**

**Files**: `lib/core/integer.rb` (Integer#<=>)
**Estimated effort**: 20 minutes

---

### 5. Implement Heap Integer Shift Operators (~2 hours) → +5-10 tests

**Current Status**: Integer#<< and Integer#>> only handle fixnum, fail on large shifts
- left_shift_spec: P:14 F:20 - many failures from `1 << 33` producing wrong values
- right_shift_spec: P:14 F:21 - similar issues

**Problem**: Current implementation uses s-expression `sall` which only works for fixnum:
```ruby
def << other
  other_raw = other.__get_raw
  %s(__int (bitand (sall other_raw (callm self __get_raw)) 0x7fffffff))
end
```

**Issues**:
- `1 << 33` produces 2 instead of 8589934592 (overflow)
- Negative shifts not handled
- Heap integer shifts not supported

**Tasks**:
- [ ] Investigate Integer#<< implementation
- [ ] Design multi-limb left shift algorithm
- [ ] Implement heap integer left shift
- [ ] Handle shift amounts exceeding fixnum range
- [ ] Handle negative shifts (delegate to >>)
- [ ] Update Integer#>> similarly

**Files**: `lib/core/integer.rb:2841-2858` (<<), `2860+` (>>)
**Estimated effort**: 2-3 hours

---

## MEDIUM PRIORITY: Parser Bugs

### Boolean Operators (`or`/`and`) Parser Bug - CAUSES CRASH

**Current Status**: times_spec CRASHES during compilation

**Impact**: times_spec crashes, blocking all tests

- [ ] Add `or` and `and` to operators list with correct precedence
- [ ] Update parser to recognize `or`/`and` as boolean operators (not method names)
- [ ] Test `a.shift or break` syntax parses correctly
- [ ] Verify times_spec no longer crashes

**Files**: `parser.rb`, `shunting.rb`, `operators.rb`
**Estimated effort**: 4-6 hours

---

### Keyword Argument Hash Literal Parser Bug - CAUSES FAILURES

**Current Status**: round_spec P:4 F:13 S:1 - does NOT crash

**Impact**: round_spec fails 13/18 tests

- [ ] Research Ruby's implicit hash syntax in method calls
- [ ] Update parser to detect `:` not part of ternary operator
- [ ] Create implicit hash node when parsing `key: value` patterns
- [ ] Test `method(half: :up)` syntax parses correctly
- [ ] Verify round_spec passes all tests

**Files**: `parser.rb`, `shunting.rb`
**Estimated effort**: 6-10 hours

---

## MEDIUM PRIORITY: Remaining Integer Operations

### Type Coercion (+20-40 tests)

**Impact**: Specs using Mock objects and mixed-type operations

- [ ] Add coercion to `Integer#*`
- [ ] Add coercion to `Integer#/`
- [ ] Add coercion to `Integer#%`
- [ ] Add coercion to `Integer#<=>` (spaceship)
- [ ] Add coercion to `Integer#==`
- [ ] Add coercion to bitwise operators (`&`, `|`, `^`, `<<`, `>>`)
- [ ] Verify plus_spec passes coercion tests
- [ ] Verify multiply_spec passes coercion tests

**Files**: `lib/core/integer.rb`
**Pattern**: Check `respond_to?(:coerce)` before `respond_to?(:to_int)` (see Session 23)
**Estimated effort**: 3-5 hours

---

### Other Integer Methods

- [ ] Implement multi-limb `Integer#<=>` (spaceship)
- [ ] Refactor comparison operators to use `<=>` (reduces duplication)
- [ ] Fix multi-limb `Integer#to_s` edge cases
- [ ] Audit heap integer methods for nil returns

**Files**: `lib/core/integer.rb`, `lib/core/fixnum.rb`

---

## LOW PRIORITY: Division Edge Cases

**Current Status (Session 33)**: Division now works! Edge cases remain:
- divide_spec: P:10 F:8
- divmod_spec: P:5 F:8
- div_spec: P:10 F:13

**Remaining Failures**:
- Negative division sign handling edge cases
- Float division (Float not implemented - expected)
- Rational division (minor off-by-one in some cases)

---

## LOW PRIORITY: Float Exception Handling

**Assessment**: LOW PRIORITY - Float not fully implemented, out of scope for integer specs

**Observed Failures**:
- div_spec: "Expected ZeroDivisionError" for `5.div(0.0)`
- divmod_spec: "Expected ZeroDivisionError" for Float 0.0
- divmod_spec: "Expected FloatDomainError if other is NaN"

**If Fixing Later**:
- [ ] Implement Float#== for zero comparison
- [ ] Implement proper Float division that raises ZeroDivisionError
- [ ] Implement FloatDomainError for NaN operations
- [ ] Update Integer#div, Integer#divmod to check Float.zero?

**Files**: `lib/core/float.rb`, `lib/core/integer.rb`
**Estimated effort**: 8-12 hours (requires Float implementation)

---

## LOW PRIORITY: pow/exponent Remaining Failures

**Current Status (Session 34)**: pow_spec and exponent_spec NOW RUN (was CRASH)!
- pow_spec: P:7 F:22 S:2 (31 total)
- exponent_spec: P:7 F:12 S:2 (21 total)

**Remaining Failures** (Expected - features not implemented):
- Modulo exponentiation: `Integer#pow(exp, modulo)` not implemented
- Float exponentiation: Float arithmetic not implemented
- Rational exponentiation: Rational arithmetic not fully implemented
- Type checking: Missing TypeError for invalid argument types

---

## LOWEST PRIORITY: Bugs Not Blocking Rubyspec

Work on these ONLY if they directly block rubyspec test improvements.

### Self-Hosted Compiler Variable Initialization

**Status**: Workaround in place (`parser.rb:155`)
- [ ] Investigate compiler.rb local variable initialization code generation
- [ ] Fix root cause so all local variables initialize to nil
- [ ] Remove workaround from parser.rb

**Files**: `compiler.rb`, `parser.rb:155-156`
**Test**: `test_uninitialized_var.rb`

---

### Ternary Operator Bug

**Issue**: Returns boolean instead of selected branch in some cases
- [ ] Investigate ternary operator compilation in `compiler.rb`
- [ ] Fix to return selected branch value, not condition result

**Test**: `test_class_new_behavior.rb`

---

## Language Features (Only If Blocking Rubyspec)

### Exception Handling Enhancements

**Status**: Basic support implemented (Session 29). Missing features:
- [ ] Implement typed rescue (`rescue SpecificError`)
- [ ] Implement rescue variable binding (`rescue => e`)
- [ ] Implement multiple rescue clauses
- [ ] Implement ensure blocks
- [ ] Implement retry support

**Files**: `lib/core/exception.rb`, `compiler.rb`
**Ref**: WORK_STATUS.md Session 29

---

### HEREDOC Syntax

**Status**: Not implemented
- [ ] Phase 1: Implement inline HEREDOC (`foo(<<HEREDOC\\n...\\nHEREDOC)`)
- [ ] Phase 2: Implement deferred HEREDOC (`foo(<<HEREDOC)\\n...\\nHEREDOC`)

**Files**: `tokens.rb`, `scanner.rb`, `parser.rb`

---

### Other Language Features

- [ ] Regular expressions (no support currently)
- [ ] Full Float arithmetic (literals work, operations stubbed)
- [ ] Keyword arguments for methods
- [ ] Method visibility (private/protected)
- [ ] alias/alias_method
- [ ] undef_method
- [ ] eval/runtime code generation (conflicts with AOT model)

---

## Architecture & Infrastructure (Not Urgent)

### Compiler Improvements
- [ ] Implement method inlining
- [ ] Add constant folding optimization
- [ ] Add dead code elimination
- [ ] Improve register allocation
- [ ] Optimize assembly patterns

### Error Reporting
- [ ] Improve compiler error messages
- [ ] Add consistent error location reporting
- [ ] Enhance parser error recovery

### Testing
- [ ] Expand self-test coverage
- [ ] Add integration tests
- [ ] Automate bootstrap verification

### Documentation
- [ ] Expand architecture documentation
- [ ] Document interfaces
- [ ] Improve code comments

---

## TODO: Systematic Failure Analysis

After completing the quick wins above, systematically analyze remaining failures:

- [ ] Run all 67 integer specs and categorize remaining failures by type
- [ ] Identify patterns in failures (missing methods, type errors, edge cases)
- [ ] Create focused tasks for each category
- [ ] Prioritize based on test impact and implementation difficulty

**Approach**:
1. Complete quick wins first (1-4 above)
2. Re-run full spec suite
3. Analyze remaining ~40 failing specs
4. Group by failure type
5. Add specific tasks to TODO

---

**Historical Completed Work**: See git log or WORK_STATUS.md for details on:
- Session 34: pow_spec/exponent_spec crash fix (carry overflow)
- Session 33: Heap integer division crash fix
- Session 32: Bitwise operators for negative numbers (two's complement)
- Earlier sessions: Various integer arithmetic fixes
