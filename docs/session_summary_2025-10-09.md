# Segfault Investigation & Fixes - Session Summary
**Date**: 2025-10-09

## Objective
Systematically investigate and fix segfaulting rubyspec/core/integer tests, grouped by root cause.

## Investigation Results

### Categorization of 43 Segfaulting Specs

**Primary Cause: Block Parameter Bug** (~19-28 specs)
- Block parameters like `|x|` are treated as method calls instead of parameters
- Confirmed: `[1,2,3].each do |x|` → "Method missing Object#x"
- This is a parser/compiler issue requiring significant changes
- **Status**: Documented but not fixed (beyond scope of quick wins)

**Secondary Cause: Missing/Broken Implementations** (Fixed: 4 specs)
- Symbol parsing for unary operators
- Bitwise operators missing assembly instructions
- Bitwise operators not re-tagging results
- Shift operators not properly implemented

**Tertiary Causes** (Documented)
- Lambda syntax edge cases (compiler has lambda support, but some patterns fail)
- Missing Mock methods for test infrastructure
- Type coercion not implemented in operators

## Fixes Implemented

### 1. Symbol Parsing for Unary Operators
**Files**: `sym.rb`
**Changes**:
- Added support for `:-@` and `:+@` symbols (lines 33-46)
- Fixed tokenizer bug where `:-@` was parsed as `:-` followed by `@`

**Impact**: 
- uminus_spec.rb: SEGFAULT → FAIL (1 spec fixed)

### 2. Bitwise Operator Assembly Instructions
**Files**: `emitter.rb`
**Changes**:
- Implemented `andl`, `orl`, `xorl` emitter methods (lines 458-460)
- These map directly to x86 AND, OR, XOR instructions

**Impact**: 
- Required for bitwise operations to generate valid assembly

### 3. Bitwise Operator Result Tagging
**Files**: `lib/core/fixnum.rb`
**Changes**:
- Wrapped `&`, `|`, `^` results in `__int()` macro (lines 170-182)
- Critical fix: bitwise operations were returning untagged integers
- Before: `%s(bitand ...)` → After: `%s(__int (bitand ...))`

**Impact**:
- allbits_spec.rb: SEGFAULT → FAIL
- anybits_spec.rb: SEGFAULT → FAIL  
- nobits_spec.rb: SEGFAULT → FAIL
- **Total: 3 specs fixed**

### 4. Shift Operators Implementation
**Files**: `compile_arithmetic.rb`, `lib/core/fixnum.rb`
**Changes**:
- Implemented `compile_sall` and `compile_sarl` (were marked "FIXME: Dummy")
- Fixed s-expression semantics: `(sall shift_amount value_to_shift)`
- Operators evaluate shift amount first, move to %ecx, then evaluate value

**Code**:
```ruby
# compile_arithmetic.rb
def compile_sall(scope, left, right)
  shift_amt = compile_eval_arg(scope, left)   # First arg = shift amount
  @e.movl(@e.result, :ecx)                     # Move to %ecx (for %cl)
  val = compile_eval_arg(scope, right)         # Second arg = value
  @e.sall(:cl, @e.result)                      # Shift by %cl
  Value.new([:subexpr])
end
```

**Impact**:
- Shift operators now work correctly for basic cases
- Verified: `1 << 5` = 32, `32 >> 2` = 8  
- left_shift_spec and right_shift_spec still segfault on edge cases (negative shifts, etc.)

### 5. Additional Stub Methods
**Files**: `lib/core/fixnum.rb`, `rubyspec_helper.rb`
**Changes**:
- Added `Fixnum#to_f` stub (returns integer, needs proper Float conversion)
- Added `Mock#stub\!` stub for test infrastructure
- Added `Mock#__get_raw` stub (see bug documentation)

## Issues Discovered & Documented

### Bitwise Operator Type Coercion Bug
**File**: `docs/bitwise_operator_coercion_bug.md`

**Problem**:
Bitwise operators call `__get_raw` directly without:
1. Checking if argument is actually a Fixnum/Integer
2. Calling `to_int` to coerce the argument
3. Handling non-Integer types properly

**Affected Tests**:
- allbits_spec.rb: "coerces the rhs using to_int"
- anybits_spec.rb: "coerces the rhs using to_int"  
- nobits_spec.rb: "coerces the rhs using to_int"

**Workaround**: Added `Mock#__get_raw` returning 0
**Status**: Documented, proper fix requires implementing coercion protocol

## Results

### Before
- Total specs: 67
- Passed: 8 (12%)
- Failed: 16 (24%)
- **Segfault: 43 (64%)**
- Failed to compile: 0

### After  
- Total specs: 67
- Passed: 8 (12%)
- Failed: 20 (30%)
- **Segfault: 39 (58%)**
- Failed to compile: 0

### Summary
- **Segfaults reduced**: 43 → 39 (9.3% improvement)
- **Specs fixed**: 4 (uminus, allbits, anybits, nobits)
- **Failures increased**: 16 → 20 (specs now run but have assertion failures)
- **Selftest**: ✅ Passing throughout all changes

## Files Modified

1. `sym.rb` - Symbol parsing for `:-@` and `:+@`
2. `emitter.rb` - Added `andl`, `orl`, `xorl` instructions
3. `lib/core/fixnum.rb` - Fixed bitwise ops, shifts, added `to_f`
4. `compile_arithmetic.rb` - Implemented `compile_sall` and `compile_sarl`
5. `rubyspec_helper.rb` - Added Mock stubs with documentation
6. `docs/TODO.md` - Updated with progress
7. `docs/segfault_analysis_2025-10-09.md` - Categorization analysis
8. `docs/bitwise_operator_coercion_bug.md` - Bug documentation
9. `docs/session_summary_2025-10-09.md` - This file

## Key Learnings

1. **Tagged Integer Arithmetic**: Fixnum representation is `(value << 1) | 1`
   - `sar` (shift arithmetic right by 1) extracts the numeric value
   - `__int` macro re-tags: `(value << 1) + 1`
   - Bitwise and shift operations must untag, operate, then re-tag

2. **x86 Shift Instructions**: Require shift count in `%cl` register
   - Cannot shift by arbitrary register
   - Must: evaluate shift amount → move to %ecx → evaluate value → shift

3. **S-Expression Evaluation Order**: Arguments evaluate left-to-right
   - `(sall A B)` evaluates A first, then B
   - Both put results in %eax, second overwrites first
   - Must save first result (e.g., move to %ecx) before evaluating second

4. **Type Coercion**: Missing throughout arithmetic/bitwise operators
   - Should call `to_int` on arguments before operating
   - Current workarounds mask real type safety issues

## Remaining Work

### High Priority (Blocks Most Specs)
- Fix block parameter handling in parser/compiler
- Implement lambda syntax edge cases
- Add type coercion to arithmetic operators

### Medium Priority (Quick Wins Available)
- Fix shift operator edge cases (negative shifts, negative numbers)
- Implement proper Float type and conversion
- Add remaining Mock methods as needed

### Low Priority (Assertion Failures)
- Fix bignum emulation (using small fixnums, produces wrong values)
- Improve stub method implementations
- Add missing core methods

## Testing Protocol Followed

After each change:
1. Manual test case to verify fix
2. Run affected rubyspec
3. Run `make selftest` to ensure no regressions
4. Document findings
5. Update TODO.md

All changes verified working with selftest passing.
