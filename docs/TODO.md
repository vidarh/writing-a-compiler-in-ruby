# Ruby Compiler TODO

**Purpose**: Task list for improving rubyspec integer test pass rate.
**Format**: One-line tasks. Details in referenced docs.
**Rule**: Only work on tasks that improve rubyspec test results.

**Current Status (Session 41)**: 28/67 specs passing (42%), 352/583 tests passing (60%)
**Previous Status (Session 40)**: 28/67 specs (42%), 343/591 tests (58%)
**Improvement**: +0 specs, +9 tests (+2% test pass rate)
**Note**: Total test count decreased 591→583 due to left_shift_spec restructure
**Goal**: Maximize test pass rate by fixing root causes

**For details**: See [RUBYSPEC_STATUS.md](RUBYSPEC_STATUS.md)
**For ongoing work**: See [WORK_STATUS.md](WORK_STATUS.md) (journaling space)
**For debugging**: See [DEBUGGING_GUIDE.md](DEBUGGING_GUIDE.md)

---

## KNOWN BUGS

### ✅ BUG 1: Integer#>> (right shift) - FIXED

**Status**: COMPLETE ✅ (Session 41, 2025-11-01)
**Impact**: Enables `>> 1` optimization for sqrt() and other algorithms with large numbers

**Implementation**:
- Integer#>> now works for both fixnums and heap integers
- Limb-based right shift with borrow propagation
- Sign extension for negative numbers
- Handles edge cases (shifts >= 31 for fixnums, shifts >= total limbs for heap)

**Results**:
- right_shift_spec: P:16 F:19 → P:30 F:8 (+14 tests, 79% pass rate)
- left_shift_spec: P:27 F:7 → P:30 F:8 (+3 tests)
- Remaining failures: edge cases with very large shifts (> 2^32)

**Actual Effort**: ~1 hour (vs 4-6 hours estimated)
**Files**: `lib/core/integer.rb` (Integer#>>, __right_shift_fixnum, __right_shift_heap, __shift_limb_right_with_borrow)
**Commit**: eb53140

### BUG 2: Integer.sqrt Performance Issues with Large Heap Integers

**Status**: Temporary workaround implemented
**Impact**: sqrt_spec test `Integer.sqrt(10**400)` causes segfault

**Root Cause**:
- Newton's method requires many iterations for very large numbers (673 for 10**400)
- Each iteration involves division and addition of huge heap integers
- Without >> optimization, uses slow `/  2` division
- Exhausts memory/crashes before completing

**Temporary Fix** (implemented):
- Added size limit: reject heap integers with > 15 limbs
- 10**121 (14 limbs) works fine
- 10**400 (45 limbs) now raises ArgumentError instead of crashing

**Proper Fix** (requires BUG 1):
1. Implement Integer#>> for heap integers
2. Replace `/ 2` with `>> 1` in sqrt algorithm
3. Should handle 10**400 and larger without issues

**Files**: `lib/core/integer.rb` (Integer.sqrt, Integer#>>)

---

## Deferred Action Plan

**Based on comprehensive failure analysis** (see [FAILURE_ANALYSIS.md](FAILURE_ANALYSIS.md))

**Session 41 Status**: All quick wins completed! bit_or_spec and bit_xor_spec now 100% passing.
**Current Blockers**:
- ⚠️ Priority 1 specs ALL require Float implementation (compiler-level changes needed)
- ⚠️ Priority 2 specs require power/multiplication accuracy fix (4-8 hours)
- ⚠️ Priority 4 (shift) requires Integer#>> for heap integers (4-6 hours, BUG 1)

**Next Steps**: Choose between Float implementation, power/multiplication fix, or Integer#>> implementation.

### Immediate Priorities (Session 41+)

**Priority 1: Specs with 1-2 Failures (Highest ROI)**:
1. ✅ **bit_or_spec** (P:12 F:0): COMPLETE - 100% passing
2. ✅ **bit_xor_spec** (P:13 F:0): COMPLETE - 100% passing
3. ⚠️ **lt_spec** (P:4 F:1): BLOCKED by Float - comparison with Float literals
4. ⚠️ **lte_spec** (P:5 F:2): BLOCKED by Float - comparison with Float literals
5. ⚠️ **case_compare_spec** (P:3 F:2): BLOCKED by Float - Float equality checks
6. ⚠️ **equal_value_spec** (P:3 F:2): BLOCKED by Float - Float equality checks
7. ⚠️ **ceildiv_spec** (P:0 F:2): BLOCKED by Float - needs Float#to_i (currently stub returns 0)

**Priority 2: Blocked by Power/Multiplication Bug**:
- **gcd_spec** (P:10 F:2): `(9999**99) % 99` returns 95 (should be 0)
- **lcm_spec** (P:9 F:2): Depends on gcd
- **modulo_spec** (P:8 F:8): Some failures due to power bug
- **Root cause**: Integer#** (power) produces incorrect results for large exponents
  - Example: `9999**13` differs from MRI around digit 24
  - Likely carry/overflow bug in heap integer multiplication
- Estimated effort: 4-8 hours to fix multiplication accuracy for very large numbers

**Priority 3: Comparison Operators (Mostly Float-related)**:
- **gt_spec** (P:2 F:3), **gte_spec** (P:2 F:3): Float comparisons
- **comparison_spec** (P:11 F:28): Bulk Float failures
- Deferred until Float implementation

**Priority 4: Shift Operators** (MOSTLY COMPLETE ✅):
- ✅ **left_shift_spec** (P:30 F:8): 79% passing (was P:27 F:7) - 8 failures are large shift edge cases
- ✅ **right_shift_spec** (P:30 F:8): 79% passing (was P:16 F:19) - 8 failures are large shift edge cases
- **Remaining**: Edge cases with shifts > 2^32 (raises "Unsupported" RangeError)

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

## MEDIUM PRIORITY

### Bitwise Operators - Two's Complement Bugs (4-8 hours)
- **bit_or_spec**: P:11 F:1 - Negative bignum OR operations
- **bit_xor_spec**: P:10 F:3 - Negative bignum XOR operations
- Root cause: `__magnitude_to_twos_complement` conversion logic bugs
- Status: DEFERRED - requires dedicated session

### Shift Operators Edge Cases (1-2 hours)
- **left_shift_spec**: P:23 F:11
- **right_shift_spec**: P:14 F:21
- Issues: negative shifts, large shift amounts, sign handling

### Division Edge Cases (2-4 hours)
- **divide_spec**: P:10 F:8
- **divmod_spec**: P:5 F:8
- **div_spec**: P:10 F:9
- **modulo_spec**: P:8 F:8
- Issues: negative division sign handling, Float division

### Remaining Crashes (1-4 hours each)
- **times_spec**: CRASH - block iteration
- **fdiv_spec**: CRASH - Float division
- **round_spec**: CRASH - Float constants

---

**Historical Completed Work**: See git log for details on Sessions 32-40
