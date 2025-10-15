# SEGFAULT Fixes - Session 2025-10-15

## Starting Status
- SEGFAULTs: 41 (regression from 13 before bignum changes)
- Goal: Make tests NOT CRASH (not necessarily pass)

## Type Safety Improvements

Added defensive type checking to prevent "Method missing NilClass#__get_raw" and "Method missing Float#__get_sign" crashes.

### Operators Fixed with Type Checking:
- `+` (addition) - Check is_a?(Integer), try to_int, check for nil
- `-` (subtraction) - Same pattern
- `*` (multiplication) - Same pattern
- `/` (division) - Same pattern
- `%` (modulo) - Type check only (no to_int)
- `&` (bitwise and) - Try to_int with nil check
- `<=>` (spaceship) - Return nil for non-Integer
- `>`, `>=`, `<`, `<=` (comparisons) - Return false for non-Integer
- `==` (equality) - Return false for non-Integer
- `**` (exponentiation) - Type check only

### Methods Fixed with Type Checking:
- `ceildiv` - Added to_int with nil check
- `div` - Added type checking
- `mul` - Added type checking
- `divmod` - Added type checking
- `gcd` - Added type checking
- `lcm` - Added type checking
- `gcdlcm` - Added type checking
- `[]` (element reference) - Added type check, implemented as `(self >> i) & 1`

### Methods Implemented:
- `remainder` - Implemented as `self - (self / other) * other`
- `rationalize` - Stub that returns self (Rational not implemented)

## Current Status
- SEGFAULTs: 33 (reduced by 8 from 41)
- Remaining crashes appear to be:
  - Test framework issues (lambda/proc/Mock)
  - Shared spec initialization problems
  - Missing test infrastructure methods

## Remaining SEGFAULT Specs (33):
ceildiv_spec, ceil_spec, comparison_spec, digits_spec, divide_spec,
divmod_spec, div_spec, downto_spec, element_reference_spec, exponent_spec,
fdiv_spec, floor_spec, gcdlcm_spec, gcd_spec, lcm_spec, lte_spec,
minus_spec, modulo_spec, multiply_spec, numerator_spec, plus_spec,
pow_spec, pred_spec, rationalize_spec, remainder_spec, round_spec,
size_spec, times_spec, to_f_spec, to_r_spec, truncate_spec,
try_convert_spec, upto_spec

## Analysis

Many specs crash during initialization before any test output appears, suggesting:
1. Shared spec helpers may have issues
2. Test framework (lambda/proc) may be broken for simple cases
3. Some specs reference unimplemented classes (Float, Rational)

Some specs run partially and show specific errors:
- `upto_spec`, `downto_spec`: "Method missing NilClass#each" (Enumerator stub returns nil)
- `remainder_spec`: Runs but tests fail, crashes on be_close (Float comparison)
- Several specs crash with FPE (floating point exception = division by zero)
