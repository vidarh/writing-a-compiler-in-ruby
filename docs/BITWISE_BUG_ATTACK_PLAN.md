# Bitwise Operations Bug: Proper Attack Plan

**Date**: 2025-10-29
**Session**: 39

## Root Cause Understanding

### Heap Integer Representation
Heap integers use **signed-magnitude** representation:
- `@limbs`: Array of **positive** limb values [0, 2^30-1]
- `@sign`: Either 1 (positive) or -1 (negative)

Example: `-5` is stored as `limbs=[5], sign=-1`

### Current Algorithm (WRONG)
The current bit_or/bit_xor implementation:
1. Converts negative operands from magnitude to two's complement
2. Performs bitwise OR/XOR on two's complement representations
3. Converts result back from two's complement to magnitude

### Why This Is Wrong

**Two's complement is a DIFFERENT representation**:
- In two's complement, `-5` is represented as `...11111011` (all bits inverted + 1)
- In signed-magnitude, `-5` is represented as `magnitude=5, sign=negative`

**The conversion is complex and error-prone**:
- Converting between representations for multi-limb numbers is non-trivial
- The current implementation has bugs in this conversion
- It's also inefficient (extra conversions)

## Correct Approach

### For Bitwise Operations on Signed-Magnitude

Ruby's bitwise operations treat negative numbers as if they were in two's complement form (infinite precision). The result semantics are:

**For OR (`|`)**:
- `positive | positive` → positive (simple limb-wise OR)
- `positive | negative` → negative (more complex)
- `negative | negative` → negative (more complex)

**For XOR (`^`)**:
- `positive ^ positive` → depends on result
- `positive ^ negative` → negative
- `negative ^ negative` → positive

**For AND (`&`)**:
- `positive & positive` → positive (simple limb-wise AND)
- `positive & negative` → positive (more complex)
- `negative & negative` → negative (more complex)

### Strategy

Instead of converting to/from two's complement, we should:

1. **Understand the mathematical relationship** between signed-magnitude and two's complement operations
2. **Implement operations directly** on signed-magnitude representation
3. **Use simpler rules** based on sign combinations

## Investigation Steps

### Step 1: Understand Current Failures (30 min)

Run specific test cases to understand what's actually happening:

```ruby
# Test 1: Simple negative OR (both small fixnums)
-5 | -3  # Expected: -3, What do we get?

# Test 2: One negative, one positive (fixnums)
5 | -3   # Expected: -3, What do we get?

# Test 3: Bignum negative OR (from failing spec)
0xbffd_ffff_ffff | -0xffff_ffff_fffd
# Expected: -55340232221128654837
# Got: -73786976294838206453
```

Create test cases and see what our implementation produces vs. what MRI Ruby produces.

### Step 2: Research Correct Algorithm (30 min)

Look up how bitwise operations should work on signed-magnitude numbers, or how to correctly convert for two's complement operations.

Options:
1. Find the mathematical formula for `magnitude_a, sign_a | magnitude_b, sign_b`
2. Find a reference implementation (e.g., GMP, MRI Ruby source)
3. Derive the correct algorithm from first principles

### Step 3: Identify Specific Bug (30 min)

Once we understand the correct algorithm, pinpoint where our implementation diverges:
- Is `__magnitude_to_twos_complement` correct?
- Is the conversion back correct?
- Is the limb extension correct?
- Is the sign calculation correct?

### Step 4: Implement Fix (1-2 hours)

Depending on findings:
- **Option A**: Fix the two's complement conversion algorithm
- **Option B**: Rewrite to work directly on signed-magnitude (simpler but more work)

### Step 5: Test and Validate (30 min)

- Test with simple cases first
- Test with failing spec cases
- Ensure bit_and still passes
- Run full spec suite

## Decision Point

Before implementing, we need to decide:

1. **Fix the two's complement approach** (current direction)
   - Pros: Less code change
   - Cons: Complex algorithm, hard to debug

2. **Rewrite to use signed-magnitude directly** (cleaner)
   - Pros: Simpler logic, matches our representation
   - Cons: More code to write, need to derive formulas

## Test Case Findings

### Fixnum Operations: ALL CORRECT ✓

Tested with -5, -3, 3, 5:
- `-5 | -3 = -1` ✓
- `5 | -3 = -3` ✓
- `-5 ^ -3 = 6` ✓
- `5 ^ -3 = -8` ✓
- `-5 & -3 = -7` ✓
- `5 & -3 = 5` ✓

**Conclusion**: Fixnum bitwise operations work perfectly. Bug is ONLY in heap integer (bignum) path.

### Heap Integer Operations: FAILURES ❌

Test cases showing failures:

| Operation | Our Result | Expected | Status |
|-----------|-----------|----------|--------|
| `1073741824 \| -1073741824` | `-814003208` | `-1073741824` | ❌ WRONG |
| `-0x8000_0000_0000_0002 \| -0x8000_0000_0000_0000` | `-9223372036854775810` | `-2` | ❌ WRONG |
| `18446744073709551627 \| -4611686018427387904` | `-73786976294838206453` | `-55340232221128654837` | ❌ WRONG (spec failure) |
| `0x8000_0000_0000_0000 ^ -0x8000_0000_0000_0002` | `-2` | `-2` | ✓ CORRECT |
| `18446744073709551627 & -4611686018427387904` | `3` | `3` | ✓ CORRECT |

**Key Observations**:
1. AND (`&`) operations work correctly
2. OR (`|`) operations fail with negative bignums
3. XOR (`^`) has mixed results
4. The bug appears when converting to/from two's complement for multi-limb numbers

### Isolated Failing Case

Minimal reproducible case:
```ruby
bignum = 18446744073709551627  # 0x10000000000000000B
negative = -4611686018427387904  # -0x40000000000000000

result = bignum | negative
# Our output: -73786976294838206453
# Expected:   -55340232221128654837
```

## Analysis Direction

The bug is in `__bitor_heap_heap` when one or both operands are negative. Since:
1. Heap integers store as signed-magnitude (`@limbs` + `@sign`)
2. The algorithm converts to two's complement for the operation
3. AND works but OR doesn't

**Hypothesis**: The two's complement conversion or the conversion back has a bug specific to OR operations, possibly related to:
- Sign extension when limb counts differ
- Handling of the result sign
- Converting two's complement back to magnitude

## Next Steps

1. ✅ Created test cases - bug isolated to heap integer OR/XOR
2. ⏭️ Analyze `__magnitude_to_twos_complement` in detail
3. ⏭️ Check if the problem is in conversion TO two's complement or FROM two's complement
4. ⏭️ Fix the specific bug
5. ⏭️ Test thoroughly

## Root Cause Identified

### The 30-bit vs 32-bit Mismatch

**Core Issue**: Limbs are 30-bit values (range [0, 2^30-1]) but the two's complement algorithm uses 32-bit operations.

**Specific Bug**:
1. `__limb_max_value` returns `4294967295` (0xFFFFFFFF - 32-bit max)
2. This value is `> 2^30-1` (1073741823), so it CANNOT fit in a fixnum
3. When storing these values in limb arrays, they overflow/wrap
4. The two's complement conversion produces incorrect results

**Evidence**:
- Test case: `1073741824 & -1073741824`
  - Expected: `1073741824`
  - Our result: `0` ❌
- Test case: `1073741824 | -1073741824`
  - Expected: `-1073741824`
  - Our result: `-759813344` ❌

Both AND and OR fail! AND just happens to pass the specific test cases in the spec.

### Why Previous 30-bit Mask Fix Failed

When I changed `__invert_limb` and `__limb_max_value` to use 30-bit masks:
- This fixed the overflow issue
- But it changed the two's complement semantics
- The algorithm needs 32-bit semantics for correctness

### The Real Solution

Need to properly handle 32-bit intermediate values while storing in 30-bit limbs:
1. **Option A**: Split 32-bit values across multiple 30-bit limbs with proper carry
2. **Option B**: Use different limb base (but this affects entire integer implementation)
3. **Option C**: Rewrite bitwise operations to avoid two's complement entirely

### Complexity

This is a FUNDAMENTAL architectural issue:
- The limb system uses 30-bit limbs
- Two's complement requires full-width operations
- Current implementation conflates these two requirements
- Fix requires careful redesign, not simple patch

## Time Estimate

- Investigation: ✅ 2 hours (DONE)
- Proper fix: 4-8 hours (requires architectural changes)
- **Status**: TOO COMPLEX for current session

## Attempted Rewrite to Signed-Magnitude

**Attempt**: Rewrote `__bitor_heap_heap` to work directly on signed-magnitude:
- Case 1 (pos|pos): Simple limb-wise OR ✓
- Case 2 (neg|neg): Use `~(a-1) | ~(b-1) = ~((a-1) & (b-1))`
- Case 3 (pos|neg): Use `pos | ~(neg-1) = ~(~pos & (neg-1))`

**Result**: SEGFAULT with heap integer test case

**Why it failed**:
- Implementation had bugs (likely in helper functions)
- Complexity of correctly implementing magnitude arithmetic
- Helpers like `__subtract_one_magnitude` and `__add_one_magnitude` need careful testing
- The signed-magnitude approach is conceptually simpler but requires more new code

**Changes reverted** ✓

## Recommendation

**Defer to future session** with dedicated time for:
1. Either: Fix the two's complement approach properly (handle 30-bit/32-bit mismatch)
2. Or: Complete signed-magnitude rewrite with incremental testing of each helper
3. Comprehensive testing of all bitwise operations
4. Consider if limb system architecture needs broader changes

**Estimated effort**: 4-8 hours for proper fix with testing

This is NOT a "quick win" - it's a significant implementation challenge requiring:
- Deep understanding of multi-limb arithmetic
- Careful handling of edge cases
- Extensive testing to avoid regressions
