# Bitwise Operations Bug: Root Cause Analysis

**Date**: 2025-10-29
**Session**: 39
**Status**: INVESTIGATION IN PROGRESS (32-bit mask theory DISPROVEN)

## Summary

The bit_or_spec and bit_xor_spec failures with negative bignums are caused by using **32-bit masks instead of 30-bit masks** in the two's complement conversion functions.

## Bug Details

### Location
File: `lib/core/integer.rb`

**Line 2579**: `__invert_limb` function
```ruby
def __invert_limb(limb)
  %s(
    (let (raw inverted)
      (assign raw (sar limb))
      (assign inverted (bitxor raw 4294967295))  # ← BUG: Using 32-bit mask
      (return (__int inverted)))
  )
end
```

**Line 2586**: `__limb_max_value` function
```ruby
def __limb_max_value
  %s(__int 4294967295)  # ← BUG: Using 32-bit max value
end
```

### The Problem

**Current values (WRONG)**:
- Mask: 4294967295 = 0xFFFFFFFF (32 bits)
- This inverts all 32 bits

**Correct values for 30-bit limbs**:
- Mask: 1073741823 = 0x3FFFFFFF (30 bits)
- Should only invert the 30 bits we use for limb storage

### Why This Causes Bugs

1. **Limbs are 30-bit values**: Range [0, 2^30-1] = [0, 1073741823]
2. **Two's complement conversion** uses `__invert_limb` to flip bits
3. **Using 32-bit mask** inverts 2 extra high-order bits that shouldn't exist
4. **These extra bits** propagate through the bitwise operations
5. **Result**: Incorrect values for negative bignum bitwise operations

### Example Failure

From `bit_or_spec.rb`:
```ruby
a = 0xbffd_ffff_ffff      # 211097642598399
b = -0xffff_ffff_fffd     # -281474976710653

result = a | b
# Expected: -55340232221128654837
# Got:      -73786976294838206453  ← WRONG due to extra bits
```

## Impact

This bug affects:
1. **bit_or_spec**: 1 failure (P:11 F:1)
2. **bit_xor_spec**: 3 failures (P:10 F:3)
3. Potentially other bitwise operations with negative bignums

## Related Code

The bug is in the two's complement conversion path:
- `__magnitude_to_twos_complement` (line 2544) - Uses `__invert_limb` and `__limb_max_value`
- `__bitor_heap_heap` (line 2842) - Calls two's complement conversion for negative operands
- `__bitxor_heap_heap` - Similar pattern

## Fix Required

**Change 1**: Update `__invert_limb` (line 2579)
```ruby
# Before:
(assign inverted (bitxor raw 4294967295))

# After:
(assign inverted (bitxor raw 1073741823))
```

**Change 2**: Update `__limb_max_value` (line 2586)
```ruby
# Before:
%s(__int 4294967295)

# After:
%s(__int 1073741823)
```

## Context: 30-bit Migration

This is a **30-bit migration related bug**:
- Phase 1 of the migration expanded fixnum range to 30 bits
- Limbs have always been 30 bits (base 2^30)
- But the two's complement conversion code was using 32-bit assumptions
- This worked "well enough" before because tests didn't cover these edge cases
- Now with expanded fixnum range, these edge cases are more visible

## Validation Plan

1. Apply both fixes
2. Recompile with `make selftest`
3. Run `./run_rubyspec rubyspec/core/integer/bit_or_spec.rb`
4. Run `./run_rubyspec rubyspec/core/integer/bit_xor_spec.rb`
5. Verify no regressions in `bit_and_spec` (currently passing)
6. Run full integer spec suite

## Risk Assessment

**Risk Level**: LOW
- Isolated change to two functions
- Clear mathematical basis (30-bit limbs = 30-bit masks)
- Fixes incorrect assumption

**Potential Issues**:
- Could affect other bitwise operations with negative numbers
- Should verify bit_and still passes (it uses same helpers)

## ATTEMPTED FIX: FAILED

**What was tried**:
1. Changed `__invert_limb` from XOR with 4294967295 to XOR with 1073741823
2. Changed `__limb_max_value` from 4294967295 to 1073741823

**Results**:
- bit_or_spec: WORSE (1 failure → 2 failures)
- bit_xor_spec: NOT TESTED (likely worse)
- bit_and_spec: BROKEN (0 failures → 1 failure) ❌
- selftest: PASSED (but specs regressed)

**Why it failed**:
The two's complement algorithm for multi-limb integers REQUIRES 32-bit operations, even though limbs themselves are 30-bit values. This is because:
- Limbs store values [0, 2^30-1]
- BUT the bitwise operations need to extend to full 32-bit width for sign extension
- Using 30-bit masks causes incorrect behavior in negative number handling

**Conclusion**: The 32-bit masks are CORRECT. The bug is elsewhere in the algorithm.

**Changes reverted** ✓

## Next Steps

1. ✅ Reverted changes - bit_and back to passing
2. Re-investigate the actual bug - likely in the algorithm logic, not the masks
3. Focus on:
   - How negative heap integers are converted to two's complement
   - How the result is converted back to magnitude form
   - Sign handling and extension logic
