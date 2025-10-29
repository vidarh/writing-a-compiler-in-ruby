# Integer Spec Failure Analysis (Session 39)

**Date**: 2025-10-29
**Context**: After 30-bit migration
**Status**: 28/67 passing (42%), 36 failing (54%), 3 crashing (4%)

## Overview

This document analyzes all 36 failing Integer specs to categorize root causes and identify improvement opportunities.

## Failure Categories

### Category 1: Float Operations & Comparisons (HIGH IMPACT)

**Specs affected**: 15+ specs, ~100+ failing tests

#### Specs with Float issues:
1. **comparison_spec.rb** (P:10 F:29) - Infinity comparisons
2. **coerce_spec.rb** (P:3 F:9) - Float coercion
3. **divide_spec.rb** (P:10 F:8) - Float division results
4. **divmod_spec.rb** (P:5 F:8) - Float in divmod
5. **div_spec.rb** (P:10 F:9) - Float division
6. **exponent_spec.rb** (P:8 F:11 S:2) - Float results from **
7. **gte_spec.rb** (P:2 F:3) - Float comparisons
8. **gt_spec.rb** (P:2 F:3) - Float comparisons
9. **integer_spec.rb** (P:1 F:3) - Float conversion
10. **left_shift_spec.rb** (P:26 F:8) - Float edge cases
11. **lte_spec.rb** (P:5 F:2) - Float comparisons
12. **lt_spec.rb** (P:3 F:2) - Float comparisons
13. **minus_spec.rb** (P:4 F:3) - Float results
14. **modulo_spec.rb** (P:8 F:8) - Float modulo
15. **multiply_spec.rb** (P:1 F:4) - Float results
16. **plus_spec.rb** (P:4 F:3) - Float results
17. **pow_spec.rb** (P:8 F:21 S:2) - Float exponentiation
18. **right_shift_spec.rb** (P:16 F:19) - Float edge cases
19. **to_f_spec.rb** (P:0 F:3) - Float conversion

#### What Float support is needed?

**Minimal requirements for Integer specs**:
1. **Float class exists** - Can create Float objects
2. **Float constants**:
   - `Float::INFINITY` (positive infinity)
   - `-Float::INFINITY` or `Float::NEG_INFINITY` (negative infinity)
3. **Integer#<=> with Float** - Return -1, 0, 1, or nil
4. **Integer#coerce(Float)** - Return [Float, Float]
5. **Float#== for comparisons** - Basic equality
6. **Float#to_s** - For error messages
7. **be_close matcher** - RSpec tolerance comparison

**NOT immediately needed**:
- Full Float arithmetic (+, -, *, /)
- Float precision/rounding
- Math functions (sin, cos, etc.)
- Float parsing from strings
- NaN support

---

### Category 2: TypeError / Type Checking (MEDIUM IMPACT)

**Specs affected**: ~10 specs, ~40 failing tests

#### Pattern:
Tests expect `TypeError` to be raised when non-numeric types are used in arithmetic, but nothing is raised (operation proceeds or crashes).

**Examples**:
- `plus_spec.rb`: "raises a TypeError when given a non-Integer"
- `multiply_spec.rb`: "raises a TypeError when given a non-Integer"
- `coerce_spec.rb`: "raises a TypeError when trying to coerce with nil"

#### What's needed:
1. Type checking in arithmetic operators
2. Raise `TypeError` with appropriate message
3. Check for `nil`, `String`, `Object` types

**Effort**: Medium - requires adding checks to each operator

---

### Category 3: Coercion Issues (MEDIUM IMPACT)

**Specs affected**: 5+ specs, ~30 failing tests

#### Specs:
- **coerce_spec.rb** (P:3 F:9) - Main coercion tests
- **comparison_spec.rb** - Coercion in comparisons
- Plus other arithmetic specs

#### What's needed:
1. Proper `Integer#coerce` implementation
2. Handle Float coercion → [Float, Float]
3. Handle failed coercion → raise TypeError or return nil
4. Exception handling in coerce

**Current state**: Some coerce support exists, but incomplete

---

### Category 4: Division & Modulo Edge Cases (LOW-MEDIUM IMPACT)

**Specs affected**: 5 specs, ~25 failing tests

#### Specs:
- **ceildiv_spec.rb** (P:0 F:2)
- **divide_spec.rb** (P:10 F:8)
- **divmod_spec.rb** (P:5 F:8)
- **div_spec.rb** (P:10 F:9)
- **modulo_spec.rb** (P:8 F:8)
- **remainder_spec.rb** (P:2 F:5)

#### Likely issues:
1. Float results not handled
2. Division by zero edge cases
3. Negative number handling
4. Bignum division edge cases

**Need to investigate**: Are these Float issues or actual arithmetic bugs?

---

### Category 5: Bit Manipulation Edge Cases (LOW IMPACT)

**Specs affected**: 3 specs, ~12 failing tests

#### Specs:
- **bit_or_spec.rb** (P:11 F:1) - Nearly passing!
- **bit_xor_spec.rb** (P:10 F:3) - Nearly passing!
- **element_reference_spec.rb** (P:17 F:17) - Bit access operator []

#### What's needed:
- Float TypeError in bit operations (bit_or, bit_xor)
- Proper [] operator for bit access
- Edge case handling

**Potential quick wins**: bit_or and bit_xor only have a few failures

---

### Category 6: Character Encoding (LOW IMPACT)

**Specs affected**: 1 spec, 17 failing tests

#### Specs:
- **chr_spec.rb** (P:9 F:17)

#### Issues:
- Character encoding support (UTF-8, etc.)
- Encoding::UndefinedConversionError
- Invalid codepoint handling

**Effort**: High - requires encoding support

---

### Category 7: Misc / Quick Wins (LOW IMPACT)

**Specs affected**: Various, ~20 failing tests

#### Specs:
- **case_compare_spec.rb** (P:3 F:2) - Float-related
- **constants_spec.rb** (P:0 F:0 S:2) - All skipped
- **downto_spec.rb** (P:4 F:5) - Block/iteration issues
- **equal_value_spec.rb** (P:3 F:2) - Float equality
- **gcd_spec.rb** (P:10 F:2) - Nearly passing!
- **lcm_spec.rb** (P:9 F:2) - Nearly passing!
- **rationalize_spec.rb** (P:3 F:2) - Rational support
- **size_spec.rb** (P:1 F:2) - Integer size reporting
- **sqrt_spec.rb** (P:4 F:3) - Square root (likely Float)
- **try_convert_spec.rb** (P:4 F:3) - Type conversion
- **upto_spec.rb** (P:4 F:5) - Block/iteration issues

---

## Impact Analysis

### High Impact (>50 tests affected)
1. **Float support** - Affects 15+ specs, ~100+ tests
   - Minimal Float class with constants
   - Basic comparison support
   - Coercion to Float

### Medium Impact (20-50 tests)
2. **TypeError checks** - Affects ~10 specs, ~40 tests
3. **Coercion improvements** - Affects 5 specs, ~30 tests
4. **Division edge cases** - Affects 5 specs, ~25 tests

### Low Impact (<20 tests)
5. **Bit operations** - 3 specs, ~12 tests (but nearly passing!)
6. **Character encoding** - 1 spec, 17 tests
7. **Misc quick wins** - Various specs, ~20 tests

---

## Minimal Float Implementation Strategy

### Goal
Unlock ~100 tests with minimal Float implementation - just enough to:
1. Make Float comparisons work
2. Handle Float coercion
3. Support Float constants (Infinity)

### Approach: "Fake Float" (Wrapper Pattern)

**Concept**: Wrap an Integer in a Float class for integer-valued floats

```ruby
class Float < Numeric
  def initialize
    @value = nil  # For tagged floats, this won't be used
  end

  # Special values as constants (not true floats, just markers)
  INFINITY = <special object>

  # Comparison - delegate to Integer
  def <=> other
    # Compare wrapped values
  end

  def == other
    # Equality check
  end

  def to_s
    # String representation
  end
end
```

**Benefits**:
- No floating-point arithmetic needed
- Integer-valued floats work (e.g., 1.0, 2.0)
- Supports comparisons
- Supports coercion

**Limitations**:
- Can't represent fractional values (0.5, 0.1, etc.)
- No float arithmetic
- No float parsing
- Good enough for many Integer specs!

### Implementation Steps

1. **Create minimal Float class** (lib/core/float.rb)
   - Empty class that exists
   - Initialize method
   - to_s method returning "<Float>"

2. **Add Float constants**
   - INFINITY as a special Integer value (e.g., MAX * 2)
   - Check if this is sufficient

3. **Test impact**
   - Run specs, see how many unlock

4. **Incrementally add features**
   - Comparison operators if needed
   - Coercion if needed
   - Only add what's necessary

### Alternative: Skip Float Tests

Instead of implementing Float, we could:
1. Modify specs to skip Float tests (NOT ALLOWED per CLAUDE.md)
2. Focus only on pure Integer tests
3. Leave Float for later

**Recommendation**: Try minimal Float class first

---

## Quick Wins (Non-Float)

### Nearly Passing Specs (need <5 fixes)

1. **bit_or_spec.rb** (P:11 F:1)
   - Only 1 failure! Likely TypeError for Float
   - **Effort**: Very low
   - **Impact**: +1 spec

2. **bit_xor_spec.rb** (P:10 F:3)
   - Only 3 failures! Likely TypeError for Float
   - **Effort**: Low
   - **Impact**: +1 spec

3. **gcd_spec.rb** (P:10 F:2)
   - Only 2 failures
   - **Effort**: Low
   - **Impact**: +1 spec

4. **lcm_spec.rb** (P:9 F:2)
   - Only 2 failures
   - **Effort**: Low
   - **Impact**: +1 spec

**Total potential**: +4 specs with minimal effort

---

## Recommended Action Plan

### Phase 1: Investigation (Current)
1. ✅ Analyze all 36 failing specs
2. ✅ Categorize by root cause
3. ✅ Identify Float requirements
4. ⏳ Design minimal Float strategy
5. ⏳ Document findings

### Phase 2: Quick Wins (Minimal Risk)
1. Fix bit_or TypeError (1 test)
2. Fix bit_xor TypeError (3 tests)
3. Investigate gcd failures (2 tests)
4. Investigate lcm failures (2 tests)
**Expected gain**: +4 specs, +8 tests

### Phase 3: Minimal Float (Medium Risk)
1. Create Float class stub
2. Add INFINITY constant
3. Test impact on specs
4. Incrementally add features as needed
**Expected gain**: +10-15 specs, +50-100 tests (if successful)

### Phase 4: TypeError Support (Medium Risk)
1. Add type checking to arithmetic ops
2. Raise TypeError appropriately
**Expected gain**: +5-10 specs, +20-40 tests

### Phase 5: Division Edge Cases (Higher Risk)
1. Investigate actual bugs
2. Fix edge cases
**Expected gain**: Variable

---

## Metrics Goals

**Current**: 28/67 (42%), 347/583 (59%)

**After Quick Wins**: 32/67 (48%), 355/583 (61%)
**After Minimal Float**: 42-47/67 (63-70%), 405-455/583 (69-78%)
**After TypeError**: 47-52/67 (70-78%), 425-495/583 (73-85%)

**Stretch Goal**: 50/67 passing (75%)

---

## Conclusion

**Biggest opportunity**: Minimal Float support could unlock ~100 tests

**Safest approach**: Start with quick wins (bit operations), then attempt Float

**Key insight**: Many "Float" failures just need Float class to exist with basic comparison - not full Float arithmetic

**Next steps**:
1. Commit this analysis
2. Attempt quick wins (bit operations)
3. Design and test minimal Float class
4. Evaluate results before proceeding further
