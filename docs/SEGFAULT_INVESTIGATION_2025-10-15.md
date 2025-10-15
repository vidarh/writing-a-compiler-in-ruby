# SEGFAULT Investigation - 2025-10-15

## Summary

Systematically checked all 41 SEGFAULT specs to identify root causes and quick wins.

### Results
- **Quick Wins Implemented**: 3 (downto, upto, round)
- **Requires Substantial Work**: 38+ specs

## Root Cause Categories

### 1. Mock/Expectation System Issues (10+ specs)
**Specs**: divide, multiply, plus, minus, divmod, allbits, anybits, bit_and, gt, gte, lt, lte

**Problem**:
- Specs use `should_receive().and_raise()` mock expectations
- Mock system not fully functional
- When operations fail, crash in error handler (FPE)

**Example Error**:
```
Mock: No expectation set for to_int
Method missing NilClass#__get_raw
Floating point exception (core dumped)
```

**Status**: SKIP - Requires fixing mock/expectation framework (complex)

### 2. Lambda/Proc Framework Issues (15+ specs)
**Specs**: ceil, floor, truncate, round, rationalize, numerator, size, times, pred, comparison, exponent

**Problem**:
- Test framework uses lambdas extensively
- Crashes at addresses like 0x1f3 (tagged fixnum values)
- Program calling through integer as if it's function pointer
- Lambda/proc infrastructure has bugs

**Example**:
```
Program received signal SIGSEGV, Segmentation fault.
0x000001f3 in ?? ()
```

**Status**: SKIP - Requires fixing lambda/proc infrastructure (complex)

### 3. Missing Methods (5+ specs)
**Specs**: fdiv, zero (needs Object#method), digits, ceildiv

**Problems**:
- fdiv: "Method missing Fixnum#fdiv"
- zero_spec: Needs Object#method() for `.method(:zero?).owner`
- digits: Missing digits() implementation

**Status**: PARTIAL - Some methods could be stubbed, but specs likely fail for other reasons too

### 4. Float Implementation Required (10+ specs)
**Specs**: downto (partial), upto (partial), fdiv, to_f, many others test Float arguments

**Problem**:
- Many specs test operations with Float arguments
- Float class exists but most operations are stubs
- Example: "Method missing Float#__get_sign"

**Status**: SKIP - Requires substantial Float implementation work

### 5. Shared Example Pattern Crashes (4+ specs)
**Specs**: divide, multiply, plus, minus (all use `:integer_arithmetic_coerce_not_rescue`)

**Problem**:
- Shared examples use advanced mock features
- `it_behaves_like()` with mocks causes crashes
- Immediate crash before any real tests run

**Status**: SKIP - Complex interaction between shared examples and mocks

## Quick Wins Achieved ✅

### 1. Integer#downto
- **Status**: ✅ IMPLEMENTED
- **Result**: 3/3 basic integer tests passing
- **Remaining Issue**: Float tests crash (expected)

### 2. Integer#upto
- **Status**: ✅ IMPLEMENTED
- **Result**: 3/3 basic integer tests passing
- **Remaining Issue**: Float tests crash (expected)

### 3. Integer#round
- **Status**: ✅ IMPLEMENTED
- **Result**: Method exists, selftest passes
- **Remaining Issue**: Spec crashes due to lambda/proc issue

### 4. Operator Nil Handling
- **Status**: ✅ IMPROVED
- **What**: * and / operators now check for nil after to_int
- **Impact**: Prevents some "Method missing NilClass#__get_raw" crashes

## Specs That Show Partial Success

### nobits_spec.rb
- **Passing**: 2/3 tests ✅
- **Crash**: Mock expectation test (expected)
- **Note**: Shows the actual method works correctly

### downto_spec.rb
- **Passing**: 3/3 integer iteration tests ✅
- **Crash**: Float tests (expected - Float not implemented)

### upto_spec.rb
- **Passing**: 3/3 integer iteration tests ✅
- **Crash**: Float tests (expected - Float not implemented)

## Detailed Spec Analysis

### Immediate FPE Crashes (div 1 0 in error handler)
- divide_spec, multiply_spec, plus_spec, minus_spec
- divmod_spec, div_spec
- gcd_spec, lcm_spec, gcdlcm_spec
- element_reference_spec, nobits_spec (partial), fdiv_spec
- to_r_spec, gt_spec, gte_spec, lt_spec, lte_spec

### Immediate SIGSEGV Crashes (lambda/proc issues)
- ceil_spec, floor_spec, truncate_spec, round_spec
- ceildiv_spec, digits_spec, rationalize_spec
- numerator_spec, size_spec, times_spec, pred_spec
- exponent_spec, pow_spec

### Specific Issues
- **zero_spec**: Needs Object#method() for `.method(:zero?).owner` test
- **fdiv_spec**: Missing fdiv() method entirely
- **comparison specs** (gt/gte/lt/lte): Mock objects passed to operators call __get_sign/__get_limbs

## Conclusion

**SEGFAULT Quick Wins Exhausted**: Most remaining SEGFAULTs require:
1. Mock/expectation system fixes (complex)
2. Lambda/proc infrastructure fixes (complex)
3. Float implementation (substantial work)
4. Various missing methods (medium complexity)

**Recommendation**: Focus on FAIL specs instead. They compile and run but produce incorrect results, often easier to fix than SEGFAULT issues.

## Methods Successfully Implemented This Session
1. Integer#** (exponentiation) ✅
2. Integer#bit_length ✅
3. Integer#downto ✅
4. Integer#upto ✅
5. Integer#round ✅
6. Improved * and / operators (nil handling) ✅
