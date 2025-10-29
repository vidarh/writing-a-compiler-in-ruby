# Quick Wins Investigation (Session 39)

**Date**: 2025-10-29
**Context**: Investigating "nearly passing" specs

## Summary

The 4 specs identified as "quick wins" (bit_or, bit_xor, gcd, lcm) are **NOT actually quick wins**. They all have actual arithmetic bugs, not simple TypeError issues.

## Findings

### bit_or_spec.rb (P:11 F:1)

**Expected**: TypeError for Float (already passing!)
**Actual failure**: Bignum bitwise OR with negative operands

```
Test: bignum | negative_bignum
Expected: -55340232221128654837
Got:      -73786976294838206453
```

**Root cause**: Bug in bitwise OR implementation for negative bignums
**Complexity**: Requires debugging bignum bitwise operations
**NOT a quick win**

---

### bit_xor_spec.rb (P:10 F:3)

**Expected**: TypeError for Float (already passing!)
**Actual failures**: Bignum bitwise XOR with negative operands (3 test cases)

```
Test 1: negative_bignum ^ positive_bignum
Expected: -55340232221128654830
Got:      -92233720377137692654

Test 2: negative_bignum ^ negative_bignum
Expected: 55340232221128654830
Got:      92233720377137692654

Test 3: all_ones ^ negative
Expected: -9903520314283042199192993792
Got:      -9903520314283042265764986880
```

**Root cause**: Bug in bitwise XOR implementation for negative bignums
**Complexity**: Requires debugging bignum bitwise operations, multiple cases
**NOT a quick win**

---

### gcd_spec.rb (P:10 F:2)

**Actual failures**: GCD returning negative values instead of positive

```
Expected: 1073741823 (positive)
Got:      -1073741823 (negative!)

Expected: 1073741824
Got:      -1073741824

Expected: 9223372036854775807
Got:      -9223372036854775807
```

**Pattern**: ALL results are negative when they should be positive
**Root cause**: Sign handling bug in GCD implementation
- Likely related to abs() not being called
- Or sign lost during algorithm
**Complexity**: Need to review GCD algorithm implementation
**NOT a quick win**

---

### lcm_spec.rb (P:9 F:2) - NOT YET TESTED

**Expectation**: Similar to GCD - likely sign issues
**Will investigate if GCD fix doesn't also fix LCM**

---

## Conclusion

**None of these are "quick wins"**. They all require:
1. Understanding bignum bitwise operations for negative numbers
2. Debugging sign handling in GCD/LCM
3. Potentially complex fixes

**Original assumption was wrong**: These specs are "nearly passing" not because they're missing simple TypeErrors, but because they have subtle arithmetic bugs.

## Updated Assessment

These failures are likely **30-bit migration related**:
- GCD sign issues with values at 30-bit boundaries (1073741823, 1073741824)
- Bitwise operations may have assumptions about bit width
- Should be investigated as potential migration regressions

## Recommendation

**Skip "quick wins" for now**. Instead:
1. Focus on **minimal Float implementation** (higher impact, ~100 tests)
2. Return to these bitwise/GCD bugs later with proper investigation
3. May need to file these as separate issues for future sessions

The Float implementation is more likely to provide actual quick gains.
