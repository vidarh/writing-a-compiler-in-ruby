# Ruby Compiler TODO

**Purpose**: Task list for improving rubyspec integer test pass rate.
**Format**: One-line tasks. Details in referenced docs.
**Rule**: Only work on tasks that improve rubyspec test results.

**IMPORTANT**: Validate tasks before starting - check if already completed.

**Current Status (Session 36)**: 20/67 specs passing (30%), 321/577 tests passing (55%)
**Previous Status**: 22/67 specs (33%), 311/609 tests (51%)
**Goal**: Maximize test pass rate by fixing root causes

**Recent Wins (Session 36)**:
- ✅ Fixed parser precedence for `-2**12`
- ✅ Resolved 21 COMPILE FAIL errors
- ✅ Fixed String#[] heap integer handling
- ✅ Fixed Integer#| and Integer#^ negative fixnum bugs (+17 tests!)

**For details**: See [RUBYSPEC_STATUS.md](RUBYSPEC_STATUS.md)
**For ongoing work**: See [WORK_STATUS.md](WORK_STATUS.md) (journaling space)
**For debugging**: See [DEBUGGING_GUIDE.md](DEBUGGING_GUIDE.md)

---

## HIGHEST PRIORITY: Quick Wins (< 30 min each)

### 1. Fix Remaining Integer#bit_length Failure (~5 min) → +1 test

**Current Status**: bit_length_spec P:3 F:1 (was P:0 F:4 - mostly fixed!)
- Only 1 failure remains after Session 35 fixes
- Likely edge case with specific bit pattern

**Fix**: Investigate the one remaining failure case in bit_length

**Impact**: bit_length_spec: P:3 F:1 → P:4 F:0 ✓ **FULL PASS (+1 test)**

**Files**: `lib/core/integer.rb` (search for `def bit_length`)
**Estimated effort**: 5 minutes

---

### 2. Add Float TypeError to Bitwise Operators (~15 min) → +10 tests, +2 specs

**Current Status**: Bitwise operators don't raise TypeError when passed Float
- bit_and_spec: P:11 F:2 - Both failures are missing TypeError for Float
- bit_or_spec: P:9 F:3 - All 3 failures are missing TypeError for Float
- bit_xor_spec: P:8 F:5 - Most failures are missing TypeError for Float

**Fix**: Add type check at start of Integer#&, Integer#|, Integer#^:
```ruby
def & other
  raise TypeError.new("Float can't be coerced into Integer") if other.is_a?(Float)
  # ... rest of implementation
end
```

**Impact**:
- bit_and_spec: P:11 F:2 → P:13 F:0 ✓ **FULL PASS (+1 spec, +2 tests)**
- bit_or_spec: P:9 F:3 → P:12 F:0 ✓ **FULL PASS (+1 spec, +3 tests)**
- bit_xor_spec: P:8 F:5 → likely P:13 F:0 ✓ (+5 tests)

**Files**: `lib/core/integer.rb` (Integer#&, Integer#|, Integer#^)
**Estimated effort**: 15 minutes

---

### 3. Fix Simple Single-Failure Specs (~10-20 min each) → +3-5 tests

**Easiest targets** (only 1 failure each):
- **zero_spec**: P:1 F:1 - Likely Integer#zero? method issue
- **ord_spec**: P:0 F:1 - Integer#ord not implemented or wrong
- **uminus_spec**: P:2 F:1 - Unary minus edge case
- **floor_spec**: P:7 F:1 - Edge case in Integer#floor

**Fix**: Investigate each spec's single failure and fix

**Impact**: +1 test each, potentially +3-4 specs to FULL PASS

**Files**: `lib/core/integer.rb`
**Estimated effort**: 10-20 minutes per spec

---

### 4. Fix Integer#=== (case_compare) (~30 min) → +1 spec PASS

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

## HIGH PRIORITY: Comparison Operators (~30 min) → +2-4 specs PASS

### Fix Comparison Operators to Raise ArgumentError (~20-30 min) → +12-16 tests

**Current Status**: Comparison operators fail or don't raise ArgumentError
- **gt_spec (>)**: P:0 F:5 - ALL failures
- **gte_spec (>=)**: P:0 F:5 - ALL failures
- **lt_spec (<)**: P:1 F:4 - Most failures
- **lte_spec (<=)**: P:3 F:4 - Half failures

**Root Cause**: Integer#<=> (spaceship) doesn't handle incomparable types correctly

**Fix**: Update Integer#<=> to raise ArgumentError for incomparable types:
```ruby
def <=> other
  # ... existing Integer comparison logic ...

  # If we reach here, other is not comparable
  raise ArgumentError.new("comparison of Integer with #{other.class} failed")
end
```

**Note**: Fixing <=> will propagate to <, >, <=, >= if they use <=> internally.

**Impact**:
- gt_spec: P:0 F:5 → P:5 F:0 ✓ **FULL PASS (+1 spec)**
- gte_spec: P:0 F:5 → P:5 F:0 ✓ **FULL PASS (+1 spec)**
- lt_spec: P:1 F:4 → P:5 F:0 ✓ **FULL PASS (+1 spec)**
- lte_spec: P:3 F:4 → P:7 F:0 ✓ **FULL PASS (+1 spec)**

**Files**: `lib/core/integer.rb` (Integer#<=>)
**Estimated effort**: 20-30 minutes

---

## MEDIUM PRIORITY: Remaining Crashes (~1-4 hours each)

### Investigate times_spec, fdiv_spec, round_spec Crashes

**Current Crashes**:
- **times_spec**: CRASH - Likely related to block iteration
- **fdiv_spec**: CRASH - Float division (Float not fully implemented)
- **round_spec**: CRASH - Rounding with precision (likely Float-related)

**Investigation**:
- Run each spec individually with gdb to get backtrace
- Identify root cause (parser bug, missing method, Float issue)
- Estimate fix effort based on root cause

**Estimated effort**: 1-4 hours per crash depending on cause

---

## MEDIUM PRIORITY: Shift Operators Improvements (~1-2 hours)

### Fix Integer#<< and Integer#>> Edge Cases

**Current Status**:
- left_shift_spec: P:23 F:11 - Good progress! (was P:14 F:20)
- right_shift_spec: P:14 F:21 - Still many failures

**Remaining Issues** (Session 35 implemented heap shifts):
- Edge cases with negative shifts
- Very large shift amounts
- Sign handling in right shift
- Overflow detection edge cases

**Impact**: +11-21 tests if fully fixed

**Files**: `lib/core/integer.rb` (Integer#<<, Integer#>>)
**Estimated effort**: 1-2 hours

---

## MEDIUM PRIORITY: Arithmetic Edge Cases (~2-4 hours)

### Division Operator Edge Cases

**Current Status**:
- divide_spec: P:10 F:8 - Half passing
- divmod_spec: P:5 F:8 - Needs work
- div_spec: P:10 F:9 - Half passing
- modulo_spec: P:8 F:8 - Half passing

**Known Issues**:
- Negative division sign handling
- Float division (Float not implemented)
- Rational edge cases
- Zero division edge cases

**Impact**: +33 tests if fully fixed

**Files**: `lib/core/integer.rb` (Integer#/, Integer#div, Integer#divmod, Integer#%)
**Estimated effort**: 2-4 hours

---

### Other Arithmetic Operators

- **plus_spec**: P:4 F:3 S:1 - Missing type checks
- **minus_spec**: P:4 F:3 - Missing type checks
- **multiply_spec**: P:1 F:4 - Missing type checks
- **pow_spec**: P:7 F:22 S:2 - Missing modulo exponentiation, type checks

**Common Fix**: Add proper type checking and coercion

**Impact**: +10-32 tests

**Estimated effort**: 2-4 hours

---

## LOW PRIORITY: Advanced Features (> 4 hours)

### Type Coercion Protocol

**Impact**: Tests using Mock objects and mixed-type operations

- [ ] Add coercion to remaining Integer arithmetic operators
- [ ] Verify coercion protocol order: `respond_to?(:coerce)` before `respond_to?(:to_int)`
- [ ] Test with mock objects

**Files**: `lib/core/integer.rb`
**Estimated effort**: 3-5 hours

---

### Other Integer Methods

- [ ] Implement Integer#ceildiv properly (P:0 F:2)
- [ ] Fix Integer#chr edge cases (P:9 F:17)
- [ ] Implement Integer#coerce edge cases (P:2 F:10)
- [ ] Fix Integer#element_reference (P:18 F:16)
- [ ] Other specialized methods

---

## LOWEST PRIORITY: Not Blocking Progress

### Float Operations

**Status**: LOW PRIORITY - Float not fully implemented

- fdiv_spec (CRASH - Float division)
- to_f_spec (P:0 F:3)
- Float type errors in various specs

**Estimated effort**: 8-12 hours (requires Float implementation)

---

### Language Features (Only If Blocking Rubyspec)

- Exception handling enhancements
- HEREDOC syntax
- Regular expressions
- Keyword arguments
- Method visibility
- eval/runtime code generation

---

## Systematic Analysis TODO

After completing quick wins (items 1-4 above):

- [ ] Re-run full spec suite
- [ ] Analyze remaining ~42 failing specs
- [ ] Group by failure type (missing methods, type errors, edge cases)
- [ ] Create focused tasks for each category
- [ ] Update TODO with specific next steps

---

**Historical Completed Work**: See git log or WORK_STATUS.md for details on:
- Session 36: Parser precedence fix, String#[] heap integers, bitwise negative fixnum fix
- Session 35: Integer#<< (left shift) implementation, Integer#bit_length fix
- Session 34: pow_spec/exponent_spec crash fix (carry overflow)
- Session 33: Heap integer division crash fix
- Session 32: Bitwise operators for negative numbers (two's complement)
