# Ruby Compiler TODO

**Purpose**: Task list for improving rubyspec integer test pass rate.
**Format**: One-line tasks. Details in referenced docs.
**Rule**: Only work on tasks that improve rubyspec test results.

**IMPORTANT**: Validate tasks before starting - check if already completed.

**Current Status (Session 39)**: 28/67 specs passing (42%), 347/583 tests passing (59%)
**Previous Status (Session 37-38)**: 25/67 specs (37%), 339/583 tests (58%)
**Improvement**: +3 specs, +8 tests (+5% spec pass rate, +1% test pass rate)
**Goal**: Maximize test pass rate by fixing root causes

**✅ COMPLETE**: 29-bit to 30-bit fixnum migration Phase 1 SUCCESSFUL
**Result**: Representational mismatch RESOLVED - all limb values can now be fixnums
**See**: [29_TO_30_BIT_MIGRATION_PLAN.md](29_TO_30_BIT_MIGRATION_PLAN.md) for details
**Achievement**: Fixnum range expanded to [-536870912, 536870911]

**Recent Wins (Sessions 37-38)**:
- ✅ Implemented Integer#=== to delegate to `other == self` for non-Integers (+6 tests)
- ✅ Fixed Integer#== to delegate to `other == self` for non-Integers
- ✅ Implemented Mock#== in rubyspec_helper (overrides Object#==)
- ✅ Added __check_comparable to Integer#<=> (validates comparable types)
- ✅ Cleaned up comparison operators (<, >, <=, >=) to use compact format
- ✅ **LESSON LEARNED**: Integer#<=> must return nil (not 0) for Float - returning 0 causes infinite loops in downto/upto

**Previous Wins (Session 37)**:
- ✅ Fixed Fixnum.class to return Integer for Ruby 2.4+ compatibility
- ✅ Fixed Integer#ord to return self for all integers
- ✅ Fixed Integer#floor edge case (0.floor(-10) now returns fixnum 0)
- ✅ Fixed Integer multiplication zero normalization (+3 specs, +3 tests!)

**For details**: See [RUBYSPEC_STATUS.md](RUBYSPEC_STATUS.md)
**For ongoing work**: See [WORK_STATUS.md](WORK_STATUS.md) (journaling space)
**For debugging**: See [DEBUGGING_GUIDE.md](DEBUGGING_GUIDE.md)

---

## ✅ COMPLETE: 29-bit to 30-bit Fixnum Migration (Session 39)

### Background
The compiler was using 29-bit fixnums (range: -2^28 to 2^28-1) but 30-bit limbs for bignum representation (range: 0 to 2^30-1). This created a **representational mismatch** where limb values in [268435456, 1073741823] could not be represented as fixnums, causing "heap integer in limbs" crashes.

### Documentation
- **[29_TO_30_BIT_MIGRATION_PLAN.md](29_TO_30_BIT_MIGRATION_PLAN.md)** - Comprehensive migration strategy
- **[29_BIT_ASSUMPTIONS_AUDIT.md](29_BIT_ASSUMPTIONS_AUDIT.md)** - Complete audit of all assumptions
- **[WORK_STATUS.md](WORK_STATUS.md)** - Session 39 details with step-by-step execution

### Phase 1: COMPLETE ✅

**Files Changed** (7 files, 8 locations):
- ✅ `lib/core/integer_base.rb` (lines 8-9): MAX/MIN constants
- ✅ `lib/core/integer.rb` (lines 15-16, 1789-1797, 1826, 1880): Constants, shift_amt, bit masks
- ✅ `lib/core/base.rb` (line 59): shift_amt in __add_with_overflow
- ✅ `tokens.rb` (lines 271, 275-277, 287): half_max constant and comments
- ✅ `lib/core/string.rb` (lines 312-314): to_i parsing limit

**Validation**: Incremental testing after each change, selftest passes, +3 spec files, +8 tests

### Results Achieved
- ✅ Fixes "heap integer in limbs" crashes - representational mismatch RESOLVED
- ✅ All limb values [0, 1073741823] now representable as fixnums
- ✅ Fixnum range expanded: [-536870912, 536870911] (2x larger)
- ✅ Improved pass rate: 37% → 42% specs, 58% → 59% tests
- ✅ System stable, selftest passes, backward compatible

### Phase 2-4: Not Needed
The migration is functionally complete. Limb operations work correctly with 30-bit fixnums. No additional phases required unless issues are discovered.

---

## Current Action Plan (Session 40)

### ✅ COMPLETE: Comparison Operator Fix

**Result**: User rewrote `__cmp_heap_fixnum` in pure Ruby, fixing the comparison bug
- ✅ Comparison bug fixed: `1073741824 <=> 0` now correctly returns 1
- ✅ Arithmetic operations validated against MRI (all correct)
- ⚠️ Discovered: sqrt_spec fails due to performance issues with large numbers

---

## KNOWN BUGS (Session 40)

### BUG 1: Integer#>> (right shift) Not Implemented for Heap Integers

**Status**: Missing implementation
**Impact**: sqrt() and other algorithms can't use `>> 1` optimization for large numbers

**Current State**:
- Integer#>> only works for tagged fixnums
- Heap integers (multi-limb bignums) return incorrect results

**Proper Fix** (deferred):
1. Implement efficient heap integer right shift by removing whole limbs until shift < 30
2. Handle remaining shift by tracking two limbs at a time
3. Shift and OR limbs together for final result

**Estimated Effort**: 4-6 hours

### BUG 2: Integer.sqrt Performance Issues with Large Heap Integers

**Status**: Temporary workaround implemented
**Impact**: sqrt_spec test `Integer.sqrt(10**400)` causes segfault

**Root Cause**:
- Newton's method requires many iterations for very large numbers (673 for 10**400)
- Each iteration involves division and addition of huge heap integers
- Without >> optimization, uses slow `/  2` division
- Exhausts memory/crashes before completing

**Temporary Fix** (implemented):
- Added size limit: reject heap integers with > 50 limbs
- 10**121 (14 limbs) works fine
- 10**400 (45 limbs) now raises ArgumentError instead of crashing

**Proper Fix** (requires BUG 1):
1. Implement Integer#>> for heap integers
2. Replace `/ 2` with `>> 1` in sqrt algorithm
3. Should handle 10**400 and larger without issues

**Files**: `lib/core/integer.rb` (Integer.sqrt, Integer#>>)

---

## Deferred Action Plan (Session 39)

**Based on comprehensive failure analysis** (see [FAILURE_ANALYSIS.md](FAILURE_ANALYSIS.md))

### Phase 1: Quick Wins (Low Risk, High Confidence) - DEFERRED
**Target**: +4 specs, +8 tests
- [ ] **bit_or_spec** (P:11 F:1) - Only 1 TypeError failure
- [ ] **bit_xor_spec** (P:10 F:3) - Only 3 TypeError failures
- [ ] **gcd_spec** (P:10 F:2) - Only 2 failures
- [ ] **lcm_spec** (P:9 F:2) - Only 2 failures

### Phase 2: Minimal Float Implementation (Medium Risk, High Impact)
**Target**: +10-15 specs, +50-100 tests
- [ ] Create minimal Float class (lib/core/float.rb)
- [ ] Add Float::INFINITY constant
- [ ] Implement basic comparison operators
- [ ] Add Integer#coerce(Float) support
- [ ] Test incremental impact

**Strategy**: "Fake Float" - wrap integers in Float class without full arithmetic
- No floating-point math needed initially
- Integer-valued floats work (1.0, 2.0)
- Unlocks ~100 tests that just need Float to exist

### Phase 3: TypeError Support (Medium Risk, Medium Impact)
**Target**: +5-10 specs, +20-40 tests
- [ ] Add type checking to arithmetic operators
- [ ] Raise TypeError for invalid types (nil, String, Object)
- [ ] Add appropriate error messages

**Stretch Goal**: 50/67 specs passing (75%)

---

## HIGHEST PRIORITY: Quick Wins (< 30 min each)

### ✅ 1. COMPLETED: Integer#=== (case_compare) - Session 37-38

**Result**: case_compare_spec P:3 F:2 (partial improvement)
- Implemented Integer#=== to delegate to `other == self` for non-Integers
- Fixed Integer#== similarly
- Fixed Mock#== in rubyspec_helper to override Object#==
- **+6 tests** (Float failures expected)

**Files Modified**: `lib/core/integer.rb`, `rubyspec_helper.rb`

---

### ✅ 2. COMPLETED: Comparison Operator Cleanup - Session 37-38

**Result**: Comparison operators cleaned up, but Float failures remain (expected)
- Added __check_comparable to Integer#<=> (validates comparable types)
- **CRITICAL LESSON**: Integer#<=> must return nil (not 0) for Float
  - Returning 0 causes infinite loops in downto/upto (segfault)
  - Returning nil makes comparisons return false/nil (safe failure)
- Cleaned up <, >, <=, >= to use compact format: `cmp = self <=> other; cmp == X`

**Current Status** (Float-related failures expected):
- **gt_spec (>)**: P:2 F:3 (3 Float failures)
- **gte_spec (>=)**: P:2 F:3 (3 Float failures)
- **lt_spec (<)**: P:3 F:2 (2 Float failures)
- **lte_spec (<=)**: P:5 F:2 (2 Float failures)

**Files Modified**: `lib/core/integer.rb` (Integer#<=>, #<, #>, #<=, #>=)

---

## MEDIUM PRIORITY: Bitwise Operators - Two's Complement Bugs (4-8 hours) - DEFERRED

### ⚠️ INVESTIGATION RESULTS (Session 38): NOT Float issues, complex two's complement bugs

**Original Claim**: "Float TypeError edge cases, ~10 minute quick win"
**Reality**: Deep two's complement conversion bugs requiring architectural fixes

**Current Status**:
- **bit_and_spec**: P:13 F:0 ✓ **PASS** (no issues)
- **bit_or_spec**: P:11 F:1 - 1 failure in bignum negative OR operations
- **bit_xor_spec**: P:10 F:3 - 3 failures in bignum negative XOR operations

**Root Cause Analysis** (Session 38):
- ALL failures occur with negative heap integers (not Float!)
- Bug is in `__magnitude_to_twos_complement` conversion logic
- Issues:
  1. Sign extension for negative operands not correct
  2. Limb width calculations (30-bit limbs with 32-bit masks)
  3. Converting back from two's complement to magnitude
- Attempted fixes caused REGRESSIONS (bit_and went from PASS to FAIL)

**Example Failures**:
- `(18446744073709551627 | -0x40000000000000000)` gives wrong result
- Expected: -55340232221128654837
- Got: -73786976294838206453

**Why This Is Hard**:
- Two's complement for multi-limb integers is complex
- Sign extension must account for variable-width numbers
- The current implementation mixes 30-bit limb storage with 32-bit bitwise operations
- Fixing one case breaks others

**Estimated Real Effort**: 4-8 hours (not 10 minutes)
- Requires deep understanding of limb representation
- Need systematic test cases for all combinations
- May require redesigning the two's complement conversion

**Files**: `lib/core/integer.rb` (__magnitude_to_twos_complement, __bitor_heap_heap, __bitxor_heap_heap)
**Status**: DEFERRED - Not a quick win, requires dedicated session

---

## MEDIUM PRIORITY: Deferred Tasks (Requires Deeper Fixes)

### Fix uminus_spec Edge Case - DEFERRED (~4+ hours)

**Current Status**: uminus_spec P:2 F:1 - One edge case failure
- Test: `(-fixnum_min) > 0` should be true but returns false
- fixnum_min = -536870912 (-2^29)
- -fixnum_min = 536870912 (2^29) - exactly at fixnum boundary

**Root Cause**: Complex limb representation issue
- Value 2^29 (536870912) exceeds fixnum range (max is 2^29-1)
- When stored in heap integer limbs array, cannot be tagged as fixnum
- Current __add_with_overflow tries to tag with __int, which overflows
- Comparison operators then misinterpret the sign

**Required Fix**: Comprehensive limb representation system changes
- Allow limbs >= 2^29 to be stored as heap integers OR raw values
- Update all limb arithmetic to handle this case
- OR: Change limb_base from 2^30 to 2^29 to match fixnum range
- This affects many heap integer operations

**Impact**: uminus_spec: P:2 F:1 → P:3 F:0 (+1 test)

**Files**: `lib/core/base.rb` (__add_with_overflow), `lib/core/integer.rb` (limb operations)
**Estimated effort**: 4+ hours (architectural change)
**Status**: DEFERRED - Requires careful design and testing

---

## MEDIUM PRIORITY: Remaining Crashes (~1-4 hours each)

### Investigate times_spec, fdiv_spec, round_spec Crashes

**Current Crashes**:
- **times_spec**: CRASH - Likely related to block iteration
- **fdiv_spec**: CRASH - Float division (Float not fully implemented)
- **round_spec**: CRASH - Rounding with precision (likely Float-related)

**Investigation**:
- Run each spec individually with gdb to get backtrace
- Identify root cause (parser bug, missing method, Float issue)
- Estimate fix effort based on root cause

**Estimated effort**: 1-4 hours per crash depending on cause

---

## MEDIUM PRIORITY: Shift Operators Improvements (~1-2 hours)

### Fix Integer#<< and Integer#>> Edge Cases

**Current Status**:
- left_shift_spec: P:23 F:11 - Good progress! (was P:14 F:20)
- right_shift_spec: P:14 F:21 - Still many failures

**Remaining Issues** (Session 35 implemented heap shifts):
- Edge cases with negative shifts
- Very large shift amounts
- Sign handling in right shift
- Overflow detection edge cases

**Impact**: +11-21 tests if fully fixed

**Files**: `lib/core/integer.rb` (Integer#<<, Integer#>>)
**Estimated effort**: 1-2 hours

---

## MEDIUM PRIORITY: Arithmetic Edge Cases (~2-4 hours)

### Division Operator Edge Cases

**Current Status**:
- divide_spec: P:10 F:8 - Half passing
- divmod_spec: P:5 F:8 - Needs work
- div_spec: P:10 F:9 - Half passing
- modulo_spec: P:8 F:8 - Half passing

**Known Issues**:
- Negative division sign handling
- Float division (Float not implemented)
- Rational edge cases
- Zero division edge cases

**Impact**: +33 tests if fully fixed

**Files**: `lib/core/integer.rb` (Integer#/, Integer#div, Integer#divmod, Integer#%)
**Estimated effort**: 2-4 hours

---

### Other Arithmetic Operators

- **plus_spec**: P:4 F:3 S:1 - Missing type checks
- **minus_spec**: P:4 F:3 - Missing type checks
- **multiply_spec**: P:1 F:4 - Missing type checks
- **pow_spec**: P:7 F:22 S:2 - Missing modulo exponentiation, type checks

**Common Fix**: Add proper type checking and coercion

**Impact**: +10-32 tests

**Estimated effort**: 2-4 hours

---

## LOW PRIORITY: Polish and Fixes

### Fix Class Name Inspect Output for Classes with ::

**Issue**: Classes with `::` in names (e.g., `Object::Integer`) have names rewritten to use `__` in assembler constants, but the inspect output/name string should show the original `::` format.

**Example**: `Object::Integer.name` should return `"Object::Integer"`, not `"Object__Integer"`

**Impact**: Low priority cosmetic fix, does not affect functionality

**Files**: Compiler symbol/class name handling
**Estimated effort**: 1-2 hours

---

## LOW PRIORITY: Advanced Features (> 4 hours)

### Type Coercion Protocol

**Impact**: Tests using Mock objects and mixed-type operations

- [ ] Add coercion to remaining Integer arithmetic operators
- [ ] Verify coercion protocol order: `respond_to?(:coerce)` before `respond_to?(:to_int)`
- [ ] Test with mock objects

**Files**: `lib/core/integer.rb`
**Estimated effort**: 3-5 hours

---

### Other Integer Methods

- [ ] Implement Integer#ceildiv properly (P:0 F:2)
- [ ] Fix Integer#chr edge cases (P:9 F:17)
- [ ] Implement Integer#coerce edge cases (P:2 F:10)
- [ ] Fix Integer#element_reference (P:18 F:16)
- [ ] Other specialized methods

---

## LOWEST PRIORITY: Not Blocking Progress

### Float Operations

**Status**: LOW PRIORITY - Float not fully implemented

- fdiv_spec (CRASH - Float division)
- to_f_spec (P:0 F:3)
- Float type errors in various specs

**Estimated effort**: 8-12 hours (requires Float implementation)

---

### Language Features (Only If Blocking Rubyspec)

- Exception handling enhancements
- HEREDOC syntax
- Regular expressions
- Keyword arguments
- Method visibility
- eval/runtime code generation

---

## Systematic Analysis TODO

After completing quick wins (items 1-4 above):

- [ ] Re-run full spec suite
- [ ] Analyze remaining ~42 failing specs
- [ ] Group by failure type (missing methods, type errors, edge cases)
- [ ] Create focused tasks for each category
- [ ] Update TODO with specific next steps

---

**Historical Completed Work**: See git log or WORK_STATUS.md for details on:
- Session 37: Fixnum.class returns Integer, Integer#ord fix, Integer#floor fix, multiplication zero normalization
- Session 36: Parser precedence fix, String#[] heap integers, bitwise negative fixnum fix
- Session 35: Integer#<< (left shift) implementation, Integer#bit_length fix
- Session 34: pow_spec/exponent_spec crash fix (carry overflow)
- Session 33: Heap integer division crash fix
- Session 32: Bitwise operators for negative numbers (two's complement)
