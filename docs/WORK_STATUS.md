# Compiler Work Status

**PURPOSE**: This is a JOURNALING SPACE for tracking ongoing work, experiments, and investigations.

**USAGE**:
- Record what you're trying, what works, what doesn't work
- Keep detailed notes during active development
- Once work is committed, TRIM this file to just completion notes
- Move historical session details to git commit messages or separate docs
- Keep only current/recent session notes (last 2-3 sessions max)

**For task lists**: See [TODO.md](TODO.md) - the canonical task list
**For overall status**: See [RUBYSPEC_STATUS.md](RUBYSPEC_STATUS.md)

---

**Last Updated**: 2025-10-31 (Session 41 - COMPLETE)
**Current Test Results**: 28/67 specs (42%), 352/583 tests (60%)
**Selftest Status**: 0 failures ✅

**Recent Progress**:
- Session 40: Fixed `__cmp_heap_fixnum`, added sqrt size limit
- Session 41: Fixed Mock#stub!, fixed `__cmp_fixnum_heap`, +9 tests (+2% pass rate)

**Next Steps**: Priority 1 specs (1-2 failures each), then modulo bug (Priority 2)

---

## Session 41: Mock#stub! and Comparison Fixes (2025-10-31) ✅ COMPLETE

### Summary

**Task**: Fix RangeError tests in left_shift_spec (user added RangeError exceptions)

**Fixes Implemented**:
1. **Mock#stub! fix**: Added `@current_method = method_name` to enable chained `.and_return()`
2. **__cmp_fixnum_heap fix**: Delegated to `__cmp_heap_fixnum` and negated result

**Results**:
- ✅ left_shift_spec: P:18 F:24 → P:27 F:7 (+9 tests)
- ✅ bit_xor_spec: P:10 F:3 → P:12 F:1 (+2 tests)
- ✅ lt_spec: P:3 F:2 → P:4 F:1 (+1 test - side effect)
- ✅ All fixnum <=> heap comparisons now work correctly
- ✅ RangeError test case in left_shift_spec now passes
- ✅ Overall: 343/591 → 352/583 tests (+9 tests, +2% pass rate)
- ✅ Selftest: 0 failures

**Investigation Results**:
- Identified modulo bug affecting gcd_spec/lcm_spec
- Categorized all 36 failing specs by priority
- Created prioritized action plan (see TODO.md)

**Key Insight**: Comparison methods don't need duplicate implementations - one can delegate to the other and negate.

### Files Modified
- `rubyspec_helper.rb`: Fixed Mock#stub! method
- `lib/core/integer.rb`: Simplified `__cmp_fixnum_heap` to delegate
- `docs/TODO.md`: Removed BUG 3 (fixed)

### Commits
- 13a7f43: Fix Mock#stub! to support chained .and_return()
- 4cb4fa1: Fix __cmp_fixnum_heap by delegating to __cmp_heap_fixnum

---

## Session 40: Comparison Operator Fix (2025-10-30/31) ✅ COMPLETE

### Summary

**Problem**: Comparison operators broken after 30-bit migration - `1073741824 <=> 0` returned -1 instead of 1

**Root Cause**: Compiler bug - assigning `@sign` instance variable to Ruby local variable outside s-expression, then using that variable inside s-expression resulted in value 0 instead of actual value.

**Solution**: User rewrote `__cmp_heap_fixnum` in pure Ruby, avoiding the compiler bug by using direct Ruby comparison operators (`@sign < 0`, `@limbs[0] < other`, etc.)

**Outcome**:
- ✅ Comparison bug fixed: `1073741824 <=> 0` now returns 1 correctly
- ✅ Selftest: 0 failures
- ✅ Selftest-c: 0 failures
- ⚠️ Discovered: sqrt_spec and left_shift_spec issues (documented as known bugs)

### Discovered Issues

**BUG 1: Integer#>> not implemented for heap integers**
- Only works for tagged fixnums
- Prevents optimization of `/ 2` → `>> 1` in algorithms
- Estimated effort: 4-6 hours

**BUG 2: Integer.sqrt performance with large numbers**
- Newton's method exhausts memory on 10**400 (673 iterations)
- Each iteration performs expensive division/addition
- Temporary fix: 15-limb size limit (raises ArgumentError)
- Proper fix requires BUG 1 (implement Integer#>>)

### Files Modified
- `lib/core/integer.rb`:
  - `__cmp_heap_fixnum`: Pure Ruby rewrite
  - `__is_heap_integer?`: Fixed tag bit check
  - `Integer.sqrt`: Added 15-limb size limit
- `docs/TODO.md`: Documented BUG 1 and BUG 2
- `docs/WORK_STATUS.md`: Session notes

### Commit
- 0fa0f25: Session 40 completion

---

## Historical Work

**Sessions 32-39**: See git log for details
- Session 39: 30-bit fixnum migration (+3 specs, +8 tests)
- Session 38: Integer#===, comparison operators, Float handling
- Session 37: Integer equality delegation
- Session 36: Parser precedence, String#[], bitwise negative fixnums
- Session 35: Integer#<< implementation
- Session 34: pow_spec crash fix (carry overflow)
- Session 33: Heap integer division crash fix
- Session 32: Bitwise operators with two's complement
