# 29-bit to 30-bit Fixnum Migration Plan

## Executive Summary

This document analyzes the migration from 29-bit to 30-bit fixnum representation and addresses the "heap integer in limbs" issue. These are TWO SEPARATE but RELATED problems that must be solved together.

## Current State (29-bit Fixnums, 30-bit Limbs)

### Fixnum Representation
- **Tagged fixnums**: Value is `(raw_value << 1) | 1`
  - Bit 0: always 1 (tag bit)
  - Bits 1-29: value bits (29 bits)
  - Bits 30-31: sign extension
- **Fixnum range**: -2^28 to 2^28-1 (-268,435,456 to 268,435,455)
- **Untagging**: `value >> 1` (arithmetic shift right, `sar`)
- **Tagging**: `__int(raw)` = `(raw << 1) | 1`

### Bignum (Heap Integer) Representation
- **Limbs**: Array of 30-bit unsigned integers (base 2^30)
- **Limb range**: 0 to 2^30-1 (0 to 1,073,741,823)
- **Sign**: Separate @sign field (+1 or -1)
- **Storage**: @limbs array + @sign

### The Fundamental Problem

**With 29-bit fixnums and 30-bit limbs, there is a REPRESENTATIONAL MISMATCH:**

```
Fixnum range:     [-268,435,456 .. 268,435,455]      (29 bits)
Limb range:       [0 .. 1,073,741,823]                (30 bits)
Problematic zone: [268,435,456 .. 1,073,741,823]     (CANNOT be fixnums!)
```

**Limb values in the range [268,435,456, 1,073,741,823] cannot be represented as fixnums!**

This creates a circular dependency:
1. Bignum arithmetic operations on limbs can produce values >= 268,435,456
2. These values need to be tagged as fixnums using `__int` for storage in @limbs array
3. But `__int(268435456)` would overflow the fixnum range!
4. This would require creating a heap integer to represent a limb
5. Which would need limbs to store it... ∞ recursion!

## Root Cause Analysis

### Where the Problem Occurs

The issue manifests in operations that:
1. Add two limbs: `limb_a + limb_b` where result >= 268,435,456
2. Multiply limbs: `limb * multiplier` producing large results
3. Shift limbs: `limb << 1` doubling values
4. Overflow detection: `sum_raw - limb_base` where adjusted value >= 268,435,456

### Critical Code Locations

**lib/core/integer.rb:729** - `__check_limb_overflow`
```ruby
# When sum_raw >= limb_base (2^30), we compute:
(assign adjusted (sub sum_raw limb_base))
# Then tag it:
(return (callm self __make_overflow_result ((__int adjusted) (__int carry_val))))
```

**Problem**: If `adjusted` >= 268,435,456, then `(__int adjusted)` produces a value outside fixnum range!

**lib/core/base.rb:59** - `__add_with_overflow`
```ruby
(assign shift_amt 29)  # Checks for 29-bit overflow
```

**Problem**: This hardcodes the assumption of 29-bit fixnums.

**lib/core/integer.rb:1795** - Multiplication overflow detection
```ruby
(assign shift_amt 29)  # Checks for 29-bit overflow
```

**Problem**: Same hardcoded assumption.

## Why It (Mostly) Works Today

Despite the representational mismatch, the system works for many cases because:

1. **Small values dominate**: Most arithmetic involves small numbers where limbs < 268,435,456
2. **Overflow handling**: `__check_limb_overflow` subtracts limb_base, keeping results bounded
3. **Careful construction**: Initial heap integer creation (in `__add_with_overflow`) extracts limbs directly via modulo/division

However, certain operations expose the bug:
- Large limb arithmetic in multiplication
- Complex division operations
- Bit manipulation on large values
- Operations that produce intermediate limb values >= 268,435,456

## The Two Problems to Solve

### Problem 1: Fixnum Range (29-bit → 30-bit)
**Goal**: Expand fixnum range to support larger immediate values

**Changes needed**:
- Update overflow detection: `shift_amt` from 29 to 30
- Update constants: MAX/MIN values
- Update documentation and comments

### Problem 2: Limb Representability
**Goal**: Ensure all valid limb values can be stored as fixnums

**This REQUIRES 30-bit fixnums** because:
- Limbs are 30-bit (0 to 2^30-1)
- ALL limb values must fit in fixnum range
- Therefore fixnums must support [0, 2^30-1]
- Which means fixnum range must be [-2^29, 2^29-1]
- Which is 30-bit signed representation

**Alternative**: Use 29-bit limbs (base 2^29)
- Limb range would be [0, 2^29-1] = [0, 536,870,911]
- All values fit in 29-bit fixnums
- BUT: Performance penalty (more limbs needed for same magnitude)
- AND: Requires rewriting ALL bignum arithmetic
- REJECTED: Too complex, 30-bit fixnums are the right solution

## Migration Strategy

### Phase 0: Preparation and Validation Setup
**Goal**: Set up temporary validation to catch bugs early

**Tasks**:
1. Add temporary crash detector in `__int` to catch overflow:
   ```ruby
   %s(defun __int (val)
     (let (result)
       (assign result (add (shl val) 1))
       # Validate: check if sign extension is correct
       # For 29-bit: bits 30-31 must equal bit 29
       # (Add validation code)
       (return result))
   )
   ```

2. Add limb value validator:
   ```ruby
   def __validate_limb(limb)
     # Check that limb is in valid range and is a fixnum
     # Temporary crash if invalid
   end
   ```

3. Create test cases for boundary conditions
4. Document baseline state

**Validation**: Run selftest and sample rubyspecs, verify expected behavior

---

### Phase 1: Update Overflow Detection (29→30 bit)
**Goal**: Change overflow detection to recognize 30-bit range

**Changes**:
1. **lib/core/base.rb:59**
   ```ruby
   - (assign shift_amt 29)
   + (assign shift_amt 30)
   ```

2. **lib/core/integer.rb:1795** (multiplication)
   ```ruby
   - (assign shift_amt 29)
   + (assign shift_amt 30)
   # Also update comment on line 1789
   - # Check if result fits in 30-bit signed range (-2^29 to 2^29-1)
   + # Check if result fits in 30-bit signed range (-2^30 to 2^30-1)
   ```

3. **lib/core/integer_base.rb:8-9** (constants)
   ```ruby
   - MAX = 268435455   # 2^28 - 1
   - MIN = -268435456  # -2^28
   + MAX = 536870911   # 2^29 - 1
   + MIN = -536870912  # -2^29
   ```

4. **lib/core/integer.rb:15-16** (duplicate constants)
   ```ruby
   - MAX = 268435455   # 2^28 - 1
   - MIN = -268435456  # -2^28
   + MAX = 536870911   # 2^29 - 1
   + MIN = -536870912  # -2^29
   ```

5. **tokens.rb:275** (parser constants)
   ```ruby
   - half_max = 268435455  # 2^28 - 1 (fits in fixnum)
   + half_max = 536870911  # 2^29 - 1 (fits in fixnum)
   ```

6. Update comments mentioning "29-bit" to "30-bit"

**DO NOT CHANGE**:
- `__limb_base_raw` (already returns 2^30)
- `__int` function (still does `(val << 1) | 1`)
- Limb arithmetic (already uses 30-bit limbs)

**Test after this phase**:
```ruby
# Test fixnum range expansion
max_old = 268435455
max_new = 536870911

# Should still work
puts max_old + 1  # Was heap, still heap

# Should now be fixnum (previously would be heap)
puts max_new      # Should work as fixnum
puts max_new + 1  # Should create heap integer
```

**Validation**:
- Run selftest - should pass
- Test boundary values
- Verify no crashes in basic arithmetic
- Check that values [268435456, 536870911] are now fixnums

**Expected issues at this phase**:
- Limb arithmetic may still crash (Phase 2 will fix)
- Some RubySpecs may still fail
- BUT: selftest should pass

---

### Phase 2: Fix Limb Tagging Issues
**Goal**: Ensure limb values are properly tagged

**Problem areas identified**:
1. `__check_limb_overflow` returns `(__int adjusted)` where adjusted could be large
2. `__check_limb_overflow_internal` similar issues
3. Any place that does `(__int limb_value)` on computed limb

**Analysis needed**:
- Search for all `(__int` calls in integer.rb
- Identify which operate on limb values
- Verify they're safe with 30-bit limbs now that fixnums are 30-bit

**Validation after Phase 1**:
With 30-bit fixnums, limb values [0, 1073741823] should ALL fit!
- `__int(1073741823)` = `(1073741823 << 1) | 1` = `2147483647`
- This is 0x7FFFFFFF (max positive 32-bit signed)
- Just barely fits in 32-bit signed integer!

**Changes**:
- Verify all limb tagging operations work correctly
- Add assertions/crashes to detect any remaining issues
- May need to adjust carry handling

**Test after this phase**:
```ruby
# Test large limb operations
a = 1073741823  # Max limb value (2^30-1)
b = 1073741823
result = a + b  # Should create heap integer with proper limb handling
puts result
```

**Validation**:
- Run integer rubyspecs
- Check multiplication, division
- Verify no "heap integer in limbs" crashes

---

### Phase 3: Remove Temporary Validation
**Goal**: Clean up temporary crash detectors and validators

**Changes**:
1. Remove validation code from `__int`
2. Remove `__validate_limb` or similar temporary checks
3. Remove debug crashes added in Phase 0
4. Clean up any temporary test files

**Validation**:
- Full selftest-c (self-hosting test)
- Full rubyspec suite
- Performance check (ensure no regression)

---

### Phase 4: Documentation and Verification
**Goal**: Update all documentation to reflect 30-bit fixnums

**Tasks**:
1. Update docs/bignums.md
2. Update docs/ARCHITECTURE.md
3. Update this document with results
4. Update TODO.md and WORK_STATUS.md
5. Add notes about the migration
6. Document any remaining issues or edge cases

---

## Risk Analysis

### Low Risk Changes
- Constant updates (MAX, MIN)
- Comment updates
- shift_amt changes (well-isolated)

### Medium Risk Changes
- Overflow detection logic
- Limb tagging operations
- Parser constant updates

### High Risk Areas
- Multiplication overflow detection (complex logic)
- Division operations (many limb manipulations)
- Bit shift operations
- Any code that assumes specific bit patterns

## Testing Strategy

### Unit Tests
- Boundary value tests for new fixnum range
- Limb overflow scenarios
- Arithmetic around boundaries

### Integration Tests
- Selftest (basic self-compilation)
- Selftest-c (full self-hosting)
- RubySpec integer suite

### Regression Prevention
- Test old boundary (268435455 ± 1)
- Test new boundary (536870911 ± 1)
- Test limb boundary (1073741823)
- Test operations that previously crashed

## Open Questions

1. **Performance impact**: Will 30-bit fixnums be slower? (Likely negligible)
2. **Memory impact**: Same number of bits used, no change expected
3. **Compatibility**: Are there external dependencies on 29-bit assumption? (Need to check)
4. **Edge cases**: Are there bit manipulation operations that assume 29-bit? (Need to audit)

## Success Criteria

- [ ] Selftest passes
- [ ] Selftest-c passes (self-hosting works)
- [ ] Integer rubyspec pass rate >= current baseline
- [ ] No crashes related to "heap integer in limbs"
- [ ] Fixnum range is [-536870912, 536870911]
- [ ] All limb values [0, 1073741823] can be stored as fixnums
- [ ] No performance regression > 5%

## References

- lib/core/integer.rb - Main integer implementation
- lib/core/integer_base.rb - Bootstrap integer
- lib/core/base.rb - Low-level overflow handlers
- tokens.rb - Parser integer constants
- docs/bignums.md - Bignum implementation documentation
- docs/WORK_STATUS.md - Historical context and previous sessions
