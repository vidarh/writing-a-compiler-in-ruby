# Bitwise Operators Issue for Heap Integers

## Problem Summary

The bitwise operators (`&`, `|`, `^`, `~`) are broken for heap integers (bignums) because they use `__get_raw`, which only works correctly for fixnums.

## Current Implementation

All bitwise operators currently use this pattern:
```ruby
other_raw = other.__get_raw
%s(__int (bitor (callm self __get_raw) other_raw))
```

## Why This Fails

`__get_raw` can only return a single 32-bit signed integer. For heap integers:
- Values >= 2^31 get truncated/mangled
- Multi-limb bignums lose all but the lowest limb
- Results are incorrect

## Evidence

Test case: `0b1010_1010 | 2147483648`
- Expected: ~2147483818 (2^31 + 170)
- Actual: 788162730 (truncated/wrong)

## Failing Tests

- `allbits_spec.rb`: 1 of 4 tests fails (negative heap integer test)
- `bit_and_spec.rb`: 8 of 13 tests fail (most bignum tests)

## Solution Approach - 3 Step Implementation

### Step 1: Make fixnum OP fixnum work correctly

For tagged fixnums, can apply bitwise operation directly:
- `(a<<1|1) | (b<<1|1) = ((a|b)<<1|1)` because `1|1 = 1`
- `(a<<1|1) & (b<<1|1) = ((a&b)<<1|1)` because `1&1 = 1`
- `(a<<1|1) ^ (b<<1|1) = ((a^b)<<1|1)` because `1^1 = 0` and we need to set the tag bit

Implementation:
```ruby
if self_is_fixnum == 1 && other_is_fixnum == 1
  %s((bitor self other))  # Works for |, &
  # For XOR: %s((bitor (bitxor self other) 1))  # Re-add tag bit
end
```

### Step 2: Make heap OP fixnum and fixnum OP heap promote fixnum to heap

Convert the fixnum to a heap integer for uniform processing:

```ruby
def __fixnum_to_heap_int(n)
  raw = n.__get_raw
  sign = raw < 0 ? -1 : 1
  if raw < 0
    raw = 0 - raw
  end

  result = Integer.new
  result.__set_heap_data([n], sign)  # Store original fixnum as single limb
  result
end
```

### Step 3: Make heap OP heap iterate over limb arrays

Limbs are fixnums, so apply operation directly:

```ruby
def __bitor_heap_heap(a, b)
  limbs_a = a.__get_limbs
  limbs_b = b.__get_limbs

  max_len = max(limbs_a.length, limbs_b.length)
  result_limbs = []

  i = 0
  while i < max_len
    limb_a = i < limbs_a.length ? limbs_a[i] : 0
    limb_b = i < limbs_b.length ? limbs_b[i] : 0

    # Limbs are fixnums - apply operation directly
    result_limb = limb_a | limb_b
    result_limbs << result_limb
    i = i + 1
  end

  # Create result heap integer or demote to fixnum
  # ...
end
```

### Key Insights

1. **Fixnums**: Tagged integers can use bitwise ops directly (tag bit is preserved)
2. **Limbs are fixnums**: No need for `__get_raw` when processing limbs
3. **Uniform processing**: Convert fixnum to heap when mixed, then process uniformly
4. **For negative integers**: Will need two's complement handling (future work)

## Implementation Challenges

- S-expressions interact poorly with Ruby if-else control flow
- Cannot use `return %s(...)` directly (compilation error)
- Must assign s-expression result to variable first, then return
- Limbs themselves are fixnums, so `__get_raw` IS appropriate when processing individual limbs

## Next Steps

1. Implement `__bitor_positive_limbs` for positive heap integer OR
2. Implement `__bitand_positive_limbs` for positive heap integer AND
3. Implement two's complement handling for negative cases
4. Test incrementally with simple cases first
5. Extend to XOR (`^`) and NOT (`~`) operators

## Code Pattern

Successful pattern for mixing s-expressions with Ruby control flow:
```ruby
if fixnum_fast_path
  result = 0
  %s((assign result (__int (bitor a b))))
  return result
end

# Heap integer path
__helper_method(...)
```

NOT:
```ruby
if condition
  %s(...)  # This doesn't return properly
else
  ...
end
```

## References

- `__add_magnitudes` in integer.rb:372 - good example of limb-by-limb processing
- `__get_limb_or_zero` - helper for safely accessing limbs
- Heap integer limbs are stored as fixnum array in `@limbs`
