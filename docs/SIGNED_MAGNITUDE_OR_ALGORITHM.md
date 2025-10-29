# Signed-Magnitude OR Algorithm

## Background

Ruby's bitwise operations treat integers as if they're in two's complement with infinite precision:
- Positive: `...00000xyz` (infinite 0s in high bits)
- Negative: `...11111xyz` (infinite 1s in high bits)

But we store as signed-magnitude:
- Positive: `magnitude=[limbs], sign=1`
- Negative: `magnitude=[limbs], sign=-1`

## Two's Complement Equivalence

For a negative number `-n`:
- Two's complement: `NOT(n-1)` with infinite 1s in high bits
- Example: `-5` = `NOT(4)` = `...1111011`

## OR Operation Rules

### Case 1: positive | positive
- Both have infinite 0s in high bits
- Result: Simple limb-wise OR
- Result sign: Positive

### Case 2: positive | negative
- Positive: `...000[limbs_p]`
- Negative: `...111[limbs_n in two's complement]`
- Result: Always negative (high bits are all 1)
- Algorithm:
  - Convert negative to two's complement: `tc_n = NOT(n-1)`
  - OR: `result_tc = limbs_p | tc_n`
  - Result has infinite 1s in high bits → negative
  - Convert back: `result_mag = NOT(result_tc) + 1`

### Case 3: negative | negative
- Both: `...111[limbs in two's complement]`
- Result: Always negative (high bits are all 1)
- Algorithm:
  - Convert both to two's complement
  - OR them
  - Convert back to magnitude

## Simplified Algorithm for OR

**Key insight**: For negative operands, we work with two's complement temporarily.

**Alternative insight**:
- `a | b` where `a < 0` in two's complement: `a | b = NOT(NOT(a) & NOT(b))`
- This is De Morgan's law: `~(~a & ~b) = a | b`

**For signed-magnitude**:
- If `a < 0`: `NOT(a)` in two's complement = `(a-1)` in magnitude
- So: `(-a) | b = NOT((a-1) & NOT(b))`

This is getting complex. Let's use the direct approach:

## Direct Two's Complement Conversion (Current Approach)

1. **positive | positive**: Simple limb-wise OR ✓
2. **positive | negative**: Convert negative to TC, OR, convert back
3. **negative | positive**: Same as above (commutative)
4. **negative | negative**: Convert both to TC, OR, convert back

## Algorithm Steps

```ruby
def bitor_signed_magnitude(a_mag, a_sign, b_mag, b_sign)
  # Case 1: Both positive - simple
  if a_sign > 0 && b_sign > 0
    result_mag = limb_wise_or(a_mag, b_mag)
    return [result_mag, 1]
  end

  # Cases with negatives: use two's complement
  # Convert negative operands to two's complement
  tc_a = a_sign < 0 ? to_twos_complement(a_mag) : a_mag
  tc_b = b_sign < 0 ? to_twos_complement(b_mag) : b_mag

  # Extend to same length (negative extends with 0xFFF..., positive with 0x000...)
  max_len = max(tc_a.length, tc_b.length)
  tc_a = extend(tc_a, max_len, a_sign < 0 ? 0xFFFFFFFF : 0)
  tc_b = extend(tc_b, max_len, b_sign < 0 ? 0xFFFFFFFF : 0)

  # OR the two's complement representations
  result_tc = limb_wise_or(tc_a, tc_b)

  # Result sign: negative if either operand is negative
  result_sign = (a_sign < 0 || b_sign < 0) ? -1 : 1

  # Convert back from two's complement if negative
  if result_sign < 0
    result_mag = from_twos_complement(result_tc)
  else
    result_mag = result_tc
  end

  return [result_mag, result_sign]
end
```

## The Bug

Looking at the current implementation, the bug is likely:
1. **Extension fill value**: When extending limbs, negative numbers should extend with `0xFFFFFFFF`, not with the result of `__magnitude_to_twos_complement` recursively
2. **Conversion back**: The conversion from two's complement back to magnitude might be using the same function, which is incorrect

The current code does: `result_limbs = __magnitude_to_twos_complement(result_limbs, ...)`
But `result_limbs` is already in two's complement! We need to convert FROM two's complement, not TO it again.

## Correct Conversion

**Magnitude → Two's Complement**: `NOT(mag) + 1`
**Two's Complement → Magnitude**: `NOT(tc) + 1` (same operation!)

So the conversion is symmetric. But the bug might be in HOW we're doing it with multi-limb numbers.
