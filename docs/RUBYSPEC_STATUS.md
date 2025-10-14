# RubySpec Test Status - 2025-10-14

## Current Status

### Test Coverage (Individual Test Cases)
```
Total test cases:    747
Passing:             142  (19%)
Failing:             605  (81%)
```

### File-Level Summary
```
Total spec files:    67
PASS:                11  (16%)
FAIL:                22  (33%)
SEGFAULT:            33  (49%)
COMPILE FAIL:         1  ( 2%)
```

## Top 3 Root Causes (Affect 80% of Failures)

### 1. Bignum Implementation Issues
**Impact**: 200+ test cases across 40+ spec files

**Problem**: Tests use fake small values instead of actual 64-bit bignums
- `bignum_value()` returns `100000 + n` instead of real heap integers
- All bignum arithmetic returns completely wrong values
- Example: Expected 18446744073709551625, Got 100009

**Broken Operators for Multi-Limb Heap Integers** (2025-10-14):

All of the following use `__get_raw` and only work correctly for single-limb heap integers:

- ❌ **Comparison**: `<=>` (spaceship), `==` (equality) - integer.rb:1603, 1855
- ❌ **Arithmetic**: `/` (division), `-@` (unary minus), `%` (modulo), `mul`, `div`, `pred`
- ❌ **Bitwise**: `&` (and), `|` (or), `^` (xor), `<<` (left shift), `>>` (right shift)
- ❌ **Other**: `abs`, `zero?`, `inspect`, `chr`
- ✅ **Fixed**: `>`, `>=`, `<`, `<=` - FIXED (2025-10-14), now properly dispatch to `__cmp_*` methods
- ✅ **Working**: `+`, `-`, `*` (binary operators work via existing heap integer implementations)

**Fix** (estimated 10-15 hours total):
1. See "Critical Prerequisite" below for large literal support (required first)
2. For each operator category, implement heap integer support:
   - Comparison: Update `<=>` to dispatch like `>`, `>=`, etc. (1 hour)
     - **Refactor opportunity**: Reimplement `>`, `>=`, `<`, `<=`, `==` in terms of `<=>`
     - Current: ~140 lines of duplicate dispatch logic across 5 operators
     - Standard Ruby: `def > other; (self <=> other) == 1; end` (~5 lines total)
     - Would save ~135 lines and improve maintainability
   - Arithmetic: Implement multi-limb division, modulo, etc. (4-6 hours)
   - Bitwise: Implement limb-by-limb bitwise operations (3-4 hours)
   - Other: Update to handle multi-limb (1-2 hours)

---

### 2. Type Coercion Missing
**Impact**: 100+ test cases across 25+ spec files

**Problem**: Operators crash on non-Integer arguments
- Call `__get_raw` without type checking
- Example: `5 & :symbol` → "Method missing Symbol#__get_raw" → crash
- No `to_int` coercion before arithmetic

**Fix**: Add type checking and coercion protocol (Phase 2, ~9 hours)

---

### 3. Method Implementation Gaps
**Impact**: 50+ test cases across 15+ spec files

**Problem**: Missing or broken methods
- `divmod` not implemented (immediate crash)
- Heap integer methods returning nil
- Negative shift operations broken

**Fix**: Implement missing methods (Phase 3, ~10 hours)

---

## Critical Prerequisite: Large Integer Literal Support

**Why This Blocks Everything**:
- Cannot fix `bignum_value()` without large literal support
- Tokenizer currently truncates integers > 2^27
- Need to parse and instantiate actual 64-bit values

**The S-Expression Constraint** 🚨 **ARCHITECTURAL REQUIREMENT**:

S-expressions **CANNOT** accept heap integers - this is not a limitation, it's a fundamental architectural constraint:

- S-expressions compile to low-level assembly operations
- Assembly expects immediate values (tagged fixnums: 30-bit signed integers)
- Heap integers are pointers to objects, not immediate values
- Using heap integers in s-expressions = memory corruption/crashes
- **Valid range in s-expressions**: -536,870,912 to 536,870,911 (-2^29 to 2^29-1)

**Implementation Order** (MUST follow this sequence):

1. **FIRST**: Add hard validation to `sexp.rb` 🚨 **MANDATORY**
   - Enforce that integer literals in s-expressions ≤ 2^29-1
   - Raise fatal error if exceeded
   - Test: `%s((add 1000000000 1))` must fail with clear error
   - Effort: 1 hour

2. **SECOND**: Audit existing code
   - `grep -r "%s" lib/ compiler*.rb | grep -E "[0-9]{9,}"`
   - Verify no large literals currently in s-expressions
   - Effort: 1 hour

3. **THIRD**: Remove tokenizer truncation
   - Parse full integer values
   - Return `[:bignum_literal, string]` for values > 2^29
   - Effort: 2-3 hours

4. **FOURTH**: Add parser/compiler support
   - Handle `[:bignum_literal, ...]` tokens
   - Generate heap integer allocation code
   - Test: `x = 9223372036854775808; puts x > 1000`
   - Effort: 2-3 hours

**Total Prerequisite Effort**: 4-8 hours

---

## Implementation Phases

### Phase 1: Bignum Foundation
**Effort**: 18-22 hours (including prerequisite)
**Expected Gain**: +27-37 test cases → 23-25% pass rate

1. Large integer literal support (4-8 hours) - **PREREQUISITE**
2. Fix `bignum_value()` helper (2 hours)
3. Fix heap integer comparison operators (8 hours)
4. Fix multi-limb to_s (4 hours)

---

### Phase 2: Type Coercion
**Effort**: 9 hours
**Expected Gain**: +40-65 test cases → 28-33% pass rate

1. Add type checking to operators (3 hours)
2. Implement to_int coercion protocol (4 hours)
3. Fix Mock object coercion (2 hours)

---

### Phase 3: Method Implementation
**Effort**: 10 hours
**Expected Gain**: +30-55 test cases → 32-40% pass rate

1. Implement divmod (3 hours)
2. Fix nil returns from heap integer methods (4 hours)
3. Fix negative shift handling (3 hours)

---

## Projected Improvement

| Milestone | Test Cases | Pass Rate | Effort |
|-----------|------------|-----------|--------|
| **Baseline** | 142/747 | 19% | - |
| After Phase 1 | 169-179/747 | 23-25% | 18-22h |
| After Phase 2 | 209-244/747 | 28-33% | 27-31h |
| After Phase 3 | 239-299/747 | 32-40% | 37-41h |

**Target**: 40% pass rate (300+ test cases) in ~40 hours of work

---

## Quick Reference

### Run Full Test Suite
```bash
./run_rubyspec rubyspec/core/integer/
```

Output includes individual test case counts:
```
Summary:
  Total spec files: 67
  Passed: 11
  Failed: 22
  Segfault/Runtime error: 33
  Failed to compile: 1

Individual Test Cases:
  Total tests: 747
  Passed: 142
  Failed: 605
  Skipped: 0
  Pass rate: 19%
```

### Run Single Spec
```bash
./run_rubyspec rubyspec/core/integer/abs_spec.rb
```

### Check for Regressions
```bash
make selftest-c
```

---

## Next Action

**Start with the critical prerequisite**: Add s-expression validation to enforce the fixnum-only constraint (1 hour, mandatory safety measure).

See `QUICK_WINS_PLAN.md` Step 1.0 for detailed implementation instructions.
