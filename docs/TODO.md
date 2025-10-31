# Ruby Compiler TODO

**Purpose**: Task list for improving rubyspec integer test pass rate.
**Format**: One-line tasks. Details in referenced docs.
**Rule**: Only work on tasks that improve rubyspec test results.

**Current Status**: 28/67 specs passing (42%), 347/583 tests passing (59%)
**Goal**: Maximize test pass rate by fixing root causes

**For details**: See [RUBYSPEC_STATUS.md](RUBYSPEC_STATUS.md)
**For ongoing work**: See [WORK_STATUS.md](WORK_STATUS.md) (journaling space)
**For debugging**: See [DEBUGGING_GUIDE.md](DEBUGGING_GUIDE.md)

---

## KNOWN BUGS

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
**Files**: `lib/core/integer.rb` (Integer#>>)

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

### Phase 1: Quick Wins (Low Risk, High Confidence)
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
