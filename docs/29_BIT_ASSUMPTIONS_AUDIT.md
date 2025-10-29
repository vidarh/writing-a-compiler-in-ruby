# 29-bit Fixnum Assumptions - Complete Audit

This document lists ALL locations in the codebase that contain hardcoded assumptions about 29-bit fixnum representation.

## Critical Constants

### lib/core/integer_base.rb
```ruby
Line 8:  MAX = 268435455   # 2^28 - 1
Line 9:  MIN = -268435456  # -2^28
```
**Action**: Update to 536870911 and -536870912

### lib/core/integer.rb
```ruby
Line 15:  MAX = 268435455   # 2^28 - 1
Line 16:  MIN = -268435456  # -2^28
```
**Action**: Update to 536870911 and -536870912

### tokens.rb
```ruby
Line 275: half_max = 268435455  # 2^28 - 1 (fits in fixnum)
```
**Action**: Update to 536870911
**Note**: Used by parser for integer literal overflow detection

```ruby
Line 287: limb_base = 268435456 * 4  # (2^28) * 4 = 2^30
```
**Action**: Update comment to "(2^29) * 2 = 2^30"
**Note**: This computation is correct (still equals 1073741824), just comment needs updating

## Overflow Detection

### lib/core/base.rb
```ruby
Line 59: (assign shift_amt 29)
```
**Context**: `__add_with_overflow` function
**Action**: Change to 30
**Impact**: Controls when addition overflows from fixnum to heap integer

### lib/core/integer.rb (Multiplication)
```ruby
Line 1789: # Check if result fits in 30-bit signed range (-2^29 to 2^29-1)
Line 1792: (assign shift_amt 31)
Line 1795: (assign shift_amt 29)
Line 1797: (assign high_bits (sarl shift_amt val))  # Bits 29-31 of low
```
**Context**: `*` operator overflow detection for fixnum multiplication
**Action**:
- Line 1789: Update comment to "(-2^30 to 2^30-1)"
- Line 1795: Change to 30
- Line 1797: Update comment to "Bits 30-31 of low"
**Impact**: Controls when multiplication overflows from fixnum to heap integer

## Bit Masking Operations

### lib/core/integer.rb
```ruby
Line 1826: (assign temp (bitand high 268435455))  # high & 0x0FFFFFFF (28 bits)
```
**Context**: Inside multiplication, extracting 28-bit portion
**Action**: Change to 536870911 (0x1FFFFFFF for 29 bits)
**Note**: This masks to extract lower bits of high word

```ruby
Line 1880: (assign temp (bitand high 268435455))  # high & 0x0FFFFFFF (28 bits)
```
**Context**: Similar bit masking in another part of multiplication
**Action**: Change to 536870911 (0x1FFFFFFF for 29 bits)

## Documentation

### docs/bignums.md
Multiple references to 29-bit fixnums throughout
**Action**: Update all references to reflect 30-bit fixnums

Key sections:
- Line 184: Example using shift_amt 29
- Line 922-927: Limb extraction examples
- Line 1401: __add_with_overflow documentation

### docs/WORK_STATUS.md
Line 390: References to 28-bit values and overflow
**Action**: Update with migration notes

## Rubyspec Tests

### rubyspec/core/integer/uminus_spec.rb
```ruby
Line 8: -268435455.should == -268435455
```
**Action**: NO CHANGE - This is testing the spec's own behavior, not our implementation
**Note**: As per CLAUDE.md rules, NEVER modify rubyspec files

## Code That DOES NOT Need Changes

### __int function (integer_base.rb:67-69)
```ruby
%s(defun __int (val)
  (add (shl val) 1)
)
```
**Action**: NO CHANGE
**Reason**: This is the tagging function - it works for any value that fits in 31 bits after shifting

### __limb_base_raw (integer.rb:684-692)
```ruby
def __limb_base_raw
  %s(
    (let (k1 k2 result)
      (assign k1 1024)
      (assign k2 (mul k1 k1))
      (assign result (mul k2 k1))  # = 1073741824 = 2^30
      (return result))
  )
end
```
**Action**: NO CHANGE
**Reason**: Already computes 2^30 correctly

### Limb arithmetic operations
Most limb operations in integer.rb do NOT need changes:
- `__check_limb_overflow` - Works with 30-bit limbs, will work better with 30-bit fixnums
- `__check_limb_borrow` - Same
- `__add_limbs_with_carry` - Already correct
- `__multiply_limb_by_fixnum_with_carry` - Already correct

**Reason**: These operations work with raw untagged values in s-expressions, then tag the result. With 30-bit fixnums, the tagging will now succeed for all valid limb values!

## Search Results Summary

### Files with "268435" (the 29-bit boundary constant)
```
tokens.rb:275 - half_max constant (CHANGE)
tokens.rb:287 - Comment only (UPDATE COMMENT)
lib/core/integer_base.rb:8-9 - MAX/MIN (CHANGE)
lib/core/integer.rb:15-16 - MAX/MIN (CHANGE)
lib/core/integer.rb:1826 - Bit mask (CHANGE)
lib/core/integer.rb:1880 - Bit mask (CHANGE)
rubyspec/core/integer/uminus_spec.rb:8 - Spec test (NO CHANGE)
lib/core/integer.rb.backup - Backup file (IGNORE)
```

### Files with "shift_amt.*29"
```
lib/core/base.rb:59 - Overflow detection (CHANGE)
lib/core/integer.rb:1795 - Multiplication overflow (CHANGE)
docs/bignums.md:184 - Documentation (UPDATE)
lib/core/integer.rb.backup - Backup file (IGNORE)
```

## Summary of Changes Needed

| File | Lines | Changes | Impact |
|------|-------|---------|--------|
| lib/core/integer_base.rb | 8-9 | Update MAX/MIN | Low - just constants |
| lib/core/integer.rb | 15-16 | Update MAX/MIN | Low - duplicate constants |
| lib/core/integer.rb | 1789,1795,1797 | Update shift_amt and comments | Medium - affects multiplication overflow |
| lib/core/integer.rb | 1826,1880 | Update bit masks | Medium - affects multiplication limb extraction |
| lib/core/base.rb | 59 | Update shift_amt | Medium - affects addition overflow |
| tokens.rb | 275 | Update half_max | Medium - affects parser |
| tokens.rb | 287 | Update comment | Low - documentation only |
| docs/bignums.md | Multiple | Update documentation | Low - documentation only |

**Total**: 8 code changes + documentation updates

## Validation Plan

After each change:
1. Run `make selftest` - must pass
2. Run boundary tests (see next section)
3. Check for crashes

After all changes:
1. Run `make selftest-c` - full self-hosting test
2. Run integer rubyspecs
3. Performance baseline check

## Boundary Test Cases

Create `test_30bit_boundaries.rb`:
```ruby
# Old boundary (no longer overflow)
old_max = 268435455
puts old_max + 1  # Should be fixnum now! (was heap before)

# New boundary (should overflow)
new_max = 536870911
puts new_max       # Should be fixnum
puts new_max + 1   # Should be heap integer

# Limb boundary (should work now)
limb_max = 1073741823  # 2^30 - 1
puts limb_max          # Should be heap integer
```

Test operations:
- Addition around boundaries
- Multiplication producing overflow
- Limb arithmetic
- Bit shifts

## Risk Assessment

**Low Risk** (2 files, 4 changes):
- integer_base.rb MAX/MIN
- integer.rb MAX/MIN
- tokens.rb comment
- Documentation

**Medium Risk** (2 files, 4 changes):
- base.rb shift_amt (well-isolated overflow check)
- tokens.rb half_max (parser boundary)
- integer.rb multiplication shift_amt
- integer.rb bit masks

**Testing Coverage**:
- Selftest provides good coverage of basic operations
- Rubyspecs test edge cases
- No high-risk changes identified

## Notes

1. **All changes are mechanical** - just updating constants and shift amounts
2. **No algorithm changes** - the logic stays the same
3. **The hard work was already done** - 30-bit limbs are already implemented
4. **Main benefit** - fixes the representational mismatch between fixnums and limbs
5. **Performance** - should be neutral or slightly better (fewer heap allocations)

## Dependencies

Must be done in order:
1. Phase 1: Update constants and shift amounts (atomic change)
2. Phase 2: Validate limb operations (should just work)
3. Phase 3: Remove temporary validation (cleanup)
4. Phase 4: Documentation (finalization)

Cannot do phases independently - constants must be updated together for consistency.
