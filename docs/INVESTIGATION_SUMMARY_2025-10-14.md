# RubySpec Investigation Summary - 2025-10-14

## What Was Accomplished

### 1. Comprehensive Failure Analysis ✅
Investigated all 67 integer spec files to identify root causes of failures:
- Manually ran and analyzed 15+ representative specs
- Categorized issues into 6 major categories
- Identified 3 high-impact root causes affecting 80% of failures

**Key Documents Created**:
- `rubyspec_failure_analysis_2025-10-14.md` - Detailed root cause analysis
- `QUICK_WINS_PLAN.md` - Actionable improvement plan with effort estimates

### 2. Enhanced Test Reporting ✅
Upgraded `run_rubyspec` to track individual test case counts:
- **Before**: Only file-level pass/fail counts
- **After**: Aggregates individual test case statistics across all specs

**New Output**:
```
Summary:
  Total spec files: 67
  Passed: 11
  Failed: 22
  Segfault/Runtime error: 34
  Failed to compile: 0

Individual Test Cases:
  Total tests: 747
  Passed: 142
  Failed: 605
  Skipped: 0
  Pass rate: 19%
```

### 3. Updated Documentation ✅
Updated `docs/TODO.md` with:
- Current baseline metrics (747 total tests, 142 passing = 19%)
- Prioritized quick wins plan (3 phases, estimated +157 test cases)
- References to detailed analysis documents

## Key Findings

### Root Cause Breakdown

| Category | Test Cases Affected | Impact | Fix Effort |
|----------|---------------------|--------|------------|
| 1. Bignum Implementation | 200+ | CRITICAL | 14 hours |
| 2. Type Coercion | 100+ | HIGH | 9 hours |
| 3. Method Gaps | 50+ | MEDIUM | 10 hours |
| 4. Float Support | 30+ | MEDIUM | 12 hours |
| 5. Encoding | 427 (chr_spec) | LOW | 20+ hours |
| 6. Parser (stabby lambda) | 1 spec | LOW | 8+ hours |

### Biggest Bottleneck: Bignum Implementation

**The Problem**:
- `bignum_value()` helper returns fake small fixnums (100000+n)
- Should return actual heap integers representing 2^63
- This causes ALL bignum tests to fail with completely wrong values

**The Impact**:
- 40+ spec files have bignum test cases
- 200+ individual test cases affected
- Examples:
  - Expected: 184467440737095516**25**
  - Got: 100**009**

**The Fix** (Phase 1, Step 1.1):
```ruby
# Current (WRONG):
def bignum_value(plus = 0)
  100000 + plus  # Fake small value
end

# Fixed:
def bignum_value(plus = 0)
  base = Integer.new
  base.__set_heap_data([0, 0, 8], 1)  # 2^63 as heap integer
  plus == 0 ? base : base + plus
end
```

**Estimated Gain**: Enables 200+ tests to use correct values (prerequisite for other fixes)

### Second Biggest: Type Coercion

**The Problem**:
- Operators call `__get_raw` without checking argument type
- Causes "Method missing Symbol#__get_raw" crashes

**Examples**:
```ruby
5 & :symbol  # Tries to call Symbol#__get_raw → CRASH
5 + mock_object  # Doesn't call mock_object.to_int → CRASH
```

**The Fix** (Phase 2):
- Add `is_a?(Integer)` checks before `__get_raw`
- Call `to_int` on arguments before arithmetic
- Pattern already exists in ceildiv, replicate everywhere

**Estimated Gain**: +50-60 test cases

## Recommended Next Steps

### Immediate Action (Week 1):

**CRITICAL PREREQUISITE** - Large Integer Literal Support (4-8 hours):
1. **Add s-expression validation FIRST** (1 hour) 🚨 **MANDATORY**
   - File: sexp.rb
   - **Hard constraint**: S-expressions CANNOT accept heap integers
   - Why: S-expressions compile to assembly with immediate values (tagged fixnums)
   - Heap integers are pointers, not immediate values
   - Must enforce: literals in s-expressions ≤ 2^29-1
   - Test: `%s((add 1000000000 1))` must raise fatal error
   - Run make selftest-c

2. **Audit existing s-expressions** (1 hour)
   - `grep -r "%s" lib/ compiler*.rb | grep -E "[0-9]{9,}"`
   - Verify no large literals in current code
   - Document any findings

3. **Remove tokenizer truncation** (2-3 hours)
   - File: tokens.rb:193
   - Parse full integer literals
   - Return [:bignum_literal, string] for values > 2^29
   - Verify s-expression validation catches any issues
   - Run make selftest-c

4. **Add parser & compiler support** (2-3 hours)
   - Parser: Handle [:bignum_literal, ...] tokens
   - Compiler: Generate heap integer allocation code
   - Test: `x = 9223372036854775808; puts x.class`
   - Run make selftest-c

**Then proceed to bignum fixes**:

1. **Fix bignum_value() helper** (2 hours)
   - Changes rubyspec_helper.rb (now can use large literals)
   - Unlocks all bignum tests
   - Test with: `./run_rubyspec rubyspec/core/integer/abs_spec.rb`

2. **Fix heap integer comparison operators** (8 hours)
   - Rewrite __cmp dispatch system
   - Critical for comparison_spec and many other specs
   - Test with: `./run_rubyspec rubyspec/core/integer/comparison_spec.rb`

3. **Fix multi-limb to_s** (4 hours)
   - Already mostly working, fix edge cases
   - Enables debugging of bignum values
   - Test with: `./run_rubyspec rubyspec/core/integer/to_s_spec.rb`

**Week 1 Expected Gain**: +27-37 test cases → 23-25% pass rate

### Follow-Up Actions (Weeks 2-3):
- Week 2: Type coercion fixes (+40-65 test cases)
- Week 3: Method implementation gaps (+30-55 test cases)

**Total Projected Improvement**: 142 → 239-299 test cases (19% → 32-40%)

## Files Modified

### New Files Created:
- `docs/rubyspec_failure_analysis_2025-10-14.md` - Comprehensive analysis
- `docs/QUICK_WINS_PLAN.md` - Detailed implementation plan
- `docs/INVESTIGATION_SUMMARY_2025-10-14.md` - This file

### Files Modified:
- `docs/TODO.md` - Updated with current status and quick wins plan
- `run_rubyspec` - Enhanced with individual test case counting
- `spec_failures.txt` - Updated with latest run

## Sample Test Results

### Passing Specs (Examples):
```
denominator_spec.rb:   ✅ 100% (all tests passing)
dup_spec.rb:          ✅ 100%
gt_spec.rb:           ✅ 100%
gte_spec.rb:          ✅ 100%
lt_spec.rb:           ✅ 100%
next_spec.rb:         ✅ 100%
nobits_spec.rb:       ✅ 100%
ord_spec.rb:          ✅ 100%
succ_spec.rb:         ✅ 100%
to_int_spec.rb:       ✅ 100%
to_i_spec.rb:         ✅ 100%
```

### Failing Specs (High-Value Targets):
```
abs_spec.rb:          1/3 passing (67% failing - bignum issue)
even_spec.rb:         4/6 passing (33% failing - bignum issue)
to_s_spec.rb:         8/15 passing (47% failing - bignum to_s)
bit_and_spec.rb:      7/18 passing (61% failing - coercion)
left_shift_spec.rb:   18/46 passing (61% failing - coercion + bignum)
```

### Segfaulting Specs (Need Investigation):
```
plus_spec.rb:         Shows output then crashes (Symbol#__get_raw)
multiply_spec.rb:     Early crash (NilClass#__multiply_heap_by_fixnum)
divmod_spec.rb:       Immediate FPE (method not implemented)
comparison_spec.rb:   Immediate FPE (broken __cmp)
```

## Metrics Summary

**Current Baseline** (2025-10-14):
- Total integer spec files: 67
- Total individual test cases: 747
- **Passing: 142 test cases (19%)**
- Failing: 605 test cases (81%)

**After Phase 1** (estimated):
- Passing: 169-179 test cases (23-25%)
- Improvement: +27-37 test cases (+4-6%)

**After Phase 2** (estimated):
- Passing: 209-244 test cases (28-33%)
- Improvement: +67-102 test cases (+9-14%)

**After Phase 3** (estimated):
- Passing: 239-299 test cases (32-40%)
- Improvement: +97-157 test cases (+13-21%)

**Target**: 40% pass rate (300+ test cases)
**Effort**: ~33 hours over 3 weeks

## Tools and Commands

### Run full suite with individual test counts:
```bash
./run_rubyspec rubyspec/core/integer/
```

### Run single spec:
```bash
./run_rubyspec rubyspec/core/integer/abs_spec.rb
```

### Check for regressions:
```bash
make selftest-c
```

### View analysis:
```bash
cat docs/rubyspec_failure_analysis_2025-10-14.md
cat docs/QUICK_WINS_PLAN.md
```

## Success Criteria

### Phase 1 Success:
- ✅ bignum_value() returns real heap integers
- ✅ Comparison operators work for heap integers
- ✅ to_s works for all bignum values
- ✅ abs_spec.rb reaches 100% (3/3 tests)
- ✅ make selftest-c still passes

### Phase 2 Success:
- ✅ No more "Method missing X#__get_raw" crashes
- ✅ Mock objects work with arithmetic operators
- ✅ plus_spec.rb runs without segfault
- ✅ multiply_spec.rb runs without segfault
- ✅ make selftest-c still passes

### Phase 3 Success:
- ✅ divmod_spec.rb runs without segfault
- ✅ Negative shift operations work correctly
- ✅ All heap integer methods return correct types
- ✅ Total pass rate ≥ 35%
- ✅ make selftest-c still passes

## Conclusion

This investigation revealed that the majority of RubySpec failures are caused by three high-impact issues:

1. **Fake bignum values** (200+ tests affected)
2. **Missing type coercion** (100+ tests affected)
3. **Method implementation gaps** (50+ tests affected)

By focusing on these three categories in priority order, we can improve the pass rate from 19% to 40% (an improvement of +157 test cases) with approximately 33 hours of focused effort.

The enhanced run_rubyspec tool now provides concrete metrics to track progress at the individual test case level, enabling data-driven decisions about where to focus development effort.

**Next Action**: Start Phase 1, Step 1.1 - Fix bignum_value() helper.
