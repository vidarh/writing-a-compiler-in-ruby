# Spec Failure Analysis - Current State

**Purpose**: Detailed supporting analysis for spec-related tasks in docs/TODO.md. Provides comprehensive categorization, root cause analysis, and impact estimates.

**Date**: 2025-10-27
**Total Specs**: 67
**Pass**: 19 (28%)
**Fail**: 47 (70%)
**Crash**: 1 (1%)

**Note**: Priorities and tasks derived from this analysis are tracked in **docs/TODO.md**. This document provides the detailed supporting information.

## Summary Statistics

From spec_failures.txt:
- **Total test cases**: 612
- **Passed**: 298 (49%)
- **Failed**: 305 (50%)
- **Skipped**: 9 (1%)

## Major Categories of Failures

### Category 1: Bignum/Heap Integer Issues (HIGH IMPACT - ~150-200 test failures)

**Symptoms:**
- Heap integer operations return wrong values (truncated to 32 bits)
- `ord` returns truncated values (e.g., 818427592 instead of 18446744073709551616)
- Large integer arithmetic is broken
- Recent multiplication changes may have introduced regressions

**Affected Specs:**
- ord_spec: Returns truncated heap integers
- left_shift_spec: Bignum shifts produce wrong results
- right_shift_spec: Bignum shifts produce wrong results
- multiply_spec: Returns 0 for large multiplications (regression from recent commits)
- divide_spec: Bignum division returns 0
- plus_spec, minus_spec: Some bignum operations fail
- All bitwise operator specs with bignums

**Root Causes:**
1. **Recent multiplication regression** - commits c66e6e2 and a64e125 introduced issues with mulfull
2. Heap integer methods may truncate to 32 bits in some operations
3. Limb calculations may be incorrect for multi-limb integers
4. Integer#ord specifically broken for heap integers

**Priority**: **CRITICAL** - Recent commits caused regressions
**Estimated Impact**: Fixing would unlock 150-200+ test cases

**Implementation Plan:**
1. **Investigate multiplication regression FIRST**
   - Review commits c66e6e2 and a64e125
   - Test: `1000000 * 1000000` should = `1000000000000`
   - May need to revert or fix the mulfull changes
   - Check if overflow detection logic is correct
   - Note: User indicated these commits are suspect but shouldn't be blindly reverted

2. Fix Integer#ord for heap integers
   - Currently returns truncated value
   - Should return the heap integer itself unchanged
   - Simple fix: just return self for heap integers

3. Audit heap integer arithmetic operations
   - Check for 32-bit truncation bugs
   - Verify limb calculations are correct
   - Test with values > 2^32

---

### Category 2: Integer#<=> (Spaceship) Returns nil (MEDIUM IMPACT - ~30-40 failures)

**Symptoms:**
- `<=>` returns `nil` for fixnum comparisons
- Should return -1, 0, or 1
- All comparison specs affected

**Affected Specs:**
- comparison_spec: 12 failures (all fixnum comparisons return nil)
- All specs that use <=> indirectly

**Root Cause:**
Integer#<=> implementation doesn't handle fixnum-to-fixnum comparisons properly.

**Priority**: **HIGH**
**Estimated Impact**: 30-40 test cases

**Implementation Plan:**
1. Review Integer#<=> in lib/core/integer.rb
2. Add fixnum <=> fixnum branch that returns -1/0/1
3. Ensure proper dispatch for heap integer comparisons
4. Test with: `5 <=> 3` (should be 1), `3 <=> 5` (should be -1), `5 <=> 5` (should be 0)

---

### Category 3: bit_length Off-By-One Errors (LOW COMPLEXITY - ~4 failures)

**Symptoms:**
- All bit_length results are off by 1
- Returns 0 when should return 1, returns 1 when should return 2, etc.

**Affected Specs:**
- bit_length_spec: ALL tests fail with consistent off-by-one error

**Root Cause:**
Implementation counts bits incorrectly, likely off-by-one in the algorithm.

**Priority**: **MEDIUM** (appears straightforward)
**Estimated Impact**: 4 test cases

**Implementation Plan:**
1. Review Integer#bit_length implementation
2. Check if counting starts at 0 vs 1
3. Likely a simple adjustment to the calculation
4. Test cases: 1 should be 1, 2 should be 2, 3 should be 2, 4 should be 3

---

### Category 4: Type Coercion Missing (MEDIUM IMPACT - ~40-50 failures)

**Symptoms:**
- TypeError not raised when it should be
- Methods don't try to_int/to_f/coerce before failing
- Mock object tests fail because coerce protocol not implemented

**Affected Specs:**
- coerce_spec: 10 failures (no exceptions, wrong return types)
- All operator specs with coerce tests (divide, multiply, bitwise, etc.)
- chr_spec: 17 failures (likely encoding + coercion issues)

**Root Causes:**
1. Integer#coerce doesn't properly handle non-numeric types
2. Binary operators don't implement coercion protocol
3. Should try: other.coerce(self) before raising TypeError

**Priority**: **MEDIUM**
**Estimated Impact**: 40-50 test cases

**Implementation Plan:**
1. Implement proper Integer#coerce
   - Try to_int for integer coercion
   - Try to_f for float coercion
   - Raise TypeError if no conversion possible

2. Add coercion to binary operators
   - Pattern: if !other.is_a?(Integer), try other.coerce(self)
   - If coerce returns [a, b], do operation with those values
   - Already partially done for some operators

---

### Category 5: Exception Raising Missing (LOW-MEDIUM IMPACT - ~30-40 failures)

**Symptoms:**
- Methods don't raise expected exceptions
- Tests expect ArgumentError, TypeError, ZeroDivisionError but nothing raised
- Some methods print to STDERR instead of raising

**Affected Specs:**
- coerce_spec: Missing TypeError/ArgumentError
- divide_spec: Missing ZeroDivisionError for integer division by zero
- ceildiv_spec: Missing exceptions
- Many specs test exception handling

**Root Cause:**
Exception handling exists but not used consistently in core methods.

**Priority**: **MEDIUM**
**Estimated Impact**: 30-40 test cases

**Implementation Plan:**
1. Add ZeroDivisionError to division methods
2. Add TypeError where type checks fail
3. Add ArgumentError where argument validation fails
4. Replace STDERR.puts with proper exceptions

---

### Category 6: Float Operation Stubs (LOW PRIORITY - ~30-40 failures)

**Symptoms:**
- Float operations return stub values (0.0, false)
- Division by Float returns 0.0 instead of actual result or Infinity
- Coerce with Float doesn't work

**Affected Specs:**
- divide_spec: Float division returns 0.0
- fdiv_spec: Mostly broken
- to_f_spec: Returns wrong type
- comparison_spec: Some Float comparison tests

**Root Cause:**
Float is not fully implemented - it's just a stub class.

**Priority**: **LOW** (large implementation effort)
**Estimated Impact**: 30-40 test cases

**Implementation Plan:**
- Document as "not implemented"
- Defer until core integer operations are solid

---

### Category 7: Negative Number Handling (MEDIUM IMPACT - ~30-40 failures)

**Symptoms:**
- Negative shift operations wrong
- Negative division wrong (returns 0 or -1 instead of correct value)
- Bitwise operations on negative numbers broken

**Affected Specs:**
- left_shift_spec: Negative shift amounts wrong
- right_shift_spec: Negative shift amounts wrong
- divide_spec: Negative division edge cases
- All bitwise specs: Negative number tests fail

**Root Cause:**
Two's complement handling may be incorrect for negative integers.

**Priority**: **MEDIUM**
**Estimated Impact**: 30-40 test cases

**Implementation Plan:**
1. Review shift operators for negative shift amounts
   - n << -m should equal n >> m
   - n >> -m should equal n << m

2. Review division for negative operands
   - Check sign handling
   - Check rounding direction

3. Review bitwise operations on negative numbers
   - Two's complement representation
   - Sign extension behavior

---

### Category 8: Rational Operations (LOW IMPACT - ~5-10 failures)

**Symptoms:**
- Rational comparisons wrong
- Rational division/operations incomplete

**Affected Specs:**
- rationalize_spec: 3 failures
- divide_spec: Some Rational tests fail

**Priority**: **LOW**
**Estimated Impact**: 5-10 test cases

---

### Category 9: Misc Small Issues (VARIES)

**Individual Issues:**
- **constants_spec**: Missing Integer::DEPRECATE_INTEGER_DIVMOD_PARAMETERS constant (2 skipped)
- **integer_spec**: Global Integer() method missing (4 failures)
- **case_compare_spec**: === operator issues (4 failures)
- **exponent_spec**: ** with special cases (15 failures, 2 skipped)
- **pow_spec**: pow method issues (25 failures, 2 skipped)
- **round_spec**: Keyword argument parsing (13 failures, 1 skipped)
- **size_spec**: Returns wrong value (2 failures)
- **sqrt_spec**: 1 failure (mostly working)
- **uminus_spec**: 1 failure
- **element_reference_spec**: [] operator with ranges (16 failures)
- **equal_value_spec**: == edge cases (4 failures)
- **to_s_spec**: 1 failure (mostly working)
- **try_convert_spec**: Integer.try_convert issues (3 failures)

---

### Category 10: Single Crash

**times_spec** - SEGFAULT
- Known parser bug: `or break` syntax
- Parser treats `or`/`and` as method calls
- Documented in TODO.md and DEBUGGING_GUIDE.md

---

## Priority Ranking

### Tier 1: Critical (Do First)
1. **Investigate and fix multiplication regression** (c66e6e2, a64e125)
   - May need careful review or partial revert
   - Affecting multiply_spec and likely other bignum operations
   - Note: Don't blindly revert - understand the issue first

2. **Fix Integer#<=>** - 30-40 tests, appears straightforward
3. **Fix Integer#ord for heap integers** - Simple fix, enables heap integer testing

### Tier 2: High Impact (Do Next)
4. **Fix bit_length off-by-one** - 4 tests, appears straightforward
5. **Implement type coercion protocol** - 40-50 tests
6. **Add exception raising** - 30-40 tests
7. **Fix negative number handling** - 30-40 tests

### Tier 3: Medium Priority
8. **Audit heap integer operations** - Many tests, but requires careful work
9. **Fix bitwise operations** - Already partially working

### Tier 4: Low Priority
10. **Float operations** - Large effort, low return
11. **Rational operations** - Small number of tests
12. **Misc small issues** - Handle individually as time permits

---

## Estimated Test Improvement Potential

| Fix Category | Estimated Tests Unlocked | Complexity |
|--------------|-------------------------|------------|
| Fix multiplication regression | 10-20 | Medium (requires investigation) |
| Integer#<=> | 30-40 | Low |
| Integer#ord | 1 | Very Low |
| bit_length off-by-one | 4 | Very Low |
| Type coercion | 40-50 | Medium |
| Exception raising | 30-40 | Low-Medium |
| Negative numbers | 30-40 | Medium |
| **Total Tier 1-2** | **~200** | **Varies** |

---

## Recommended Approach

1. **Start with investigation**
   - Review multiplication commits c66e6e2 and a64e125
   - Understand what changed with mulfull
   - Create minimal test case to reproduce issue
   - Determine if partial fix or revert is needed

2. **Quick wins**
   - Integer#<=> fixnum branch
   - Integer#ord for heap integers
   - bit_length off-by-one

3. **Systematic improvements**
   - Type coercion protocol
   - Exception raising
   - Negative number handling

4. **Continuous validation**
   - Run `make selftest-c` after each change
   - Test individual specs as fixes are applied
   - Monitor for regressions

