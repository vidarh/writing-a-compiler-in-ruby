# RubySpec Failure Analysis - 2025-10-14

## Executive Summary

**Current Status**: 67 integer spec files
- **PASS**: 11 files (16%)
- **FAIL**: 22 files (33%)
- **SEGFAULT**: 33 files (49%)
- **COMPILE FAIL**: 1 file (1%)

**Individual Test Cases** (estimated from sampling):
- **Total test cases**: ~500-600 individual tests across all specs
- **Passing**: ~100-150 individual tests (20-25%)
- **Failing**: ~350-450 individual tests (75-80%)

## Root Cause Categories

### 1. Bignum Implementation Issues ⚠️ CRITICAL (affects 40+ specs, 200+ test cases)

**Impact**: This is the single largest cause of failures. Nearly every spec has bignum-related test cases that fail.

**Symptoms**:
- `bignum_value()` helper returns 100000+n instead of actual 64-bit bignum values
- Bignum arithmetic returns completely wrong values (e.g., Expected 184467440 but got 100009)
- Bignum `to_s` returns "1" or small fixnum strings instead of proper large number strings
- Multi-limb heap integers display wrong values

**Examples**:
- `abs_spec.rb`: 1 pass, 2 fails - both fails are bignum tests
- `even_spec.rb`: 4 pass, 2 fails - both fails are bignum tests
- `to_s_spec.rb`: 8 pass, 7 fails - all fails are bignum to_s conversions
  - Expected "18446744073709551625" but got "100009"
  - Expected "10000000000000000000000000000000000000000000000000000000000000000" but got "1"
- `plus_spec.rb`: Shows "Expected 184467440 but got 100009"
- `left_shift_spec.rb`: Expected 236118324 but got 12800000
- `bit_and_spec.rb`: Expected 184467440 but got 1

**Root Causes**:
1. **Fake bignum_value() helper** (rubyspec_helper.rb:534)
   - Returns `100000 + plus` instead of `0x8000_0000_0000_0000 + plus`
   - This is intentional workaround but causes all bignum tests to fail
   - Comment says: "These values allow tests to run but don't actually test bignum behavior"

2. **Incomplete bignum implementation** (docs/bignums.md)
   - Multi-limb support exists but has bugs
   - Comparison operators broken for heap integers
   - to_s for multi-limb values has issues
   - Fixnum-as-receiver dispatcher bug affects fixnum × heap

3. **Known bignum limitations**:
   - Comparison operators (`<`, `>`, `<=`, `>=`) broken for heap integers
   - `__cmp` dispatch system fails silently
   - Workaround exists (`__is_negative`) but doesn't cover all cases

**Quick Wins**:
1. Fix `bignum_value()` to return actual heap integer objects (not fake 100000+n values)
2. Fix multi-limb to_s bugs (already mostly working)
3. Fix comparison operators for heap integers
4. This alone could convert 100+ failing tests to passing

### 2. Type Coercion Issues ⚠️ CRITICAL (affects 25+ specs, 100+ test cases)

**Impact**: Causes segfaults and type errors across many operator tests.

**Symptoms**:
- "TypeError: Integer can't be coerced into Integer"
- "Method missing Symbol#__get_raw"
- "Method missing NilClass#__multiply_heap_by_fixnum"
- FPE (Floating Point Exception) crashes

**Examples**:
- `plus_spec.rb`: "Method missing Symbol#__get_raw" → FPE
- `multiply_spec.rb`: "Method missing NilClass#__multiply_heap_by_fixnum" → FPE
- `bit_and_spec.rb`: "TypeError: Integer can't be coerced" in coercion tests
- `left_shift_spec.rb`: "TypeError: Integer can't be coerced" when testing to_int conversion

**Root Causes**:
1. **Operators call `__get_raw` without type checking** (known issue in docs/DEBUGGING_GUIDE.md:230)
   - `&`, `|`, `^`, `<<`, `>>` all call `__get_raw` directly
   - If argument is not Integer, calls method on wrong type → crash
   - Example: `5 & :symbol` tries to call `Symbol#__get_raw` which doesn't exist

2. **Missing to_int coercion protocol**
   - Operators should call `to_int` on arguments before using them
   - Some operators partially fixed (ceildiv), others not

3. **Mock objects don't implement required methods**
   - Added `Mock#__get_raw` workaround but not comprehensive
   - Need proper coercion protocol instead

**Quick Wins**:
1. Add type checking before `__get_raw` calls in all operators
2. Implement to_int coercion protocol consistently
3. This could fix 50+ test failures and prevent ~10 segfaults

### 3. Float Support Issues (affects 10+ specs, 30+ test cases)

**Impact**: Medium - blocks Float-related tests but doesn't affect integer-only operations.

**Symptoms**:
- Float operations return integers instead of floats
- "Expected 0.0 but got 1002" (integer returned instead of float)
- to_f returns integer instead of Float object

**Examples**:
- `plus_spec.rb`: "Expected 0.0 but got 1002"
- `to_f_spec.rb`: Segfaults (float operations not implemented)
- `fdiv_spec.rb`: Segfaults (float division not implemented)

**Root Causes**:
1. Float class exists but arithmetic operations are stubs
2. `to_f` returns `self` (integer) instead of converting to Float
3. Float literals work but operations don't

**Quick Wins**:
1. Implement basic Float arithmetic (add, subtract, multiply, divide)
2. Fix `to_f` to actually return Float objects
3. Lower priority than bignum/coercion issues

### 4. Method Implementation Gaps (affects 15+ specs)

**Impact**: Medium - each missing method causes specific test failures.

**Symptoms**:
- Immediate segfaults/FPEs with no output
- Method missing errors

**Examples**:
- `divmod_spec.rb`: Immediate FPE (no output before crash)
- `comparison_spec.rb`: Immediate FPE
- `multiply_spec.rb`: "Method missing NilClass#__multiply_heap_by_fixnum"

**Root Causes**:
1. `divmod` method not implemented or broken
2. Some heap integer methods return nil when they should return objects
3. Method dispatch issues (methods exist but called on wrong object)

**Quick Wins**:
1. Implement/fix `divmod` method
2. Audit heap integer methods to ensure they return correct types
3. Fix method dispatch for heap integer operations

### 5. Encoding Issues (affects 1 spec heavily: chr_spec.rb)

**Impact**: Low for core integer functionality, high for chr_spec specifically.

**Symptoms**:
- Multi-byte UTF-8 sequences wrong or empty
- Expected `[227, 128, 128]` but got `[]`
- Expected `[194, 128]` but got `[128]`
- Encoding object identity issues

**Examples**:
- `chr_spec.rb`: 15 pass, 427 fails - nearly all failures are encoding-related

**Root Causes**:
1. String encoding implementation incomplete
2. Multi-byte character handling not implemented
3. Encoding object caching/identity broken

**Quick Wins**:
- LOW PRIORITY - encoding is orthogonal to integer functionality
- Focus on bignum/coercion issues first

### 6. Parser Issues (affects 1 spec: digits_spec.rb)

**Impact**: Very low - only affects one spec file.

**Symptoms**:
- Compilation hangs/infinite loop
- Timeout after 2 minutes

**Example**:
- `digits_spec.rb`: Uses stabby lambda `->` syntax, causes infinite compilation loop

**Root Cause**:
- Stabby lambda syntax (`->`) not supported by parser
- Parser enters infinite loop instead of reporting error

**Quick Wins**:
- Can work around by rewriting lambdas in spec file
- Or skip this spec until parser supports `->`

## Impact Analysis by Spec File

### High-Impact Quick Wins (Fix 1-2 issues, gain 20+ passing test cases each):

1. **to_s_spec.rb** (currently 8/15 passing)
   - Fix: Bignum to_s implementation
   - Gain: +7 test cases (47% → 100%)

2. **bit_and_spec.rb** (currently 7/18 passing)
   - Fix: Type coercion + bignum bitwise ops
   - Gain: +11 test cases (39% → 100%)

3. **left_shift_spec.rb** (currently 18/46 passing)
   - Fix: Type coercion + bignum shifts + negative shift handling
   - Gain: +28 test cases (39% → 100%)

4. **abs_spec.rb** (currently 1/3 passing)
   - Fix: Bignum abs implementation
   - Gain: +2 test cases (33% → 100%)

5. **even_spec.rb** (currently 4/6 passing)
   - Fix: Bignum even? predicate
   - Gain: +2 test cases (67% → 100%)

### Medium-Impact Fixes (Currently segfault, could gain 10-50 test cases each):

1. **plus_spec.rb** (currently segfaults)
   - Fix: Type coercion (Symbol#__get_raw error)
   - Estimated: 20-30 test cases

2. **multiply_spec.rb** (currently segfaults)
   - Fix: Nil return value from heap integer method
   - Estimated: 15-25 test cases

3. **divmod_spec.rb** (currently segfaults)
   - Fix: Implement divmod method
   - Estimated: 10-20 test cases

4. **comparison_spec.rb** (currently segfaults)
   - Fix: Heap integer comparison operators
   - Estimated: 20-30 test cases

### Low-Priority (Encoding-heavy or complex):

1. **chr_spec.rb** (currently 15/442 passing)
   - Requires: Full encoding implementation
   - Effort: High, gain: 1 spec file

2. **digits_spec.rb** (currently compile fail)
   - Requires: Stabby lambda parser support or manual rewrite
   - Effort: Medium-High, gain: 1 spec file

## Recommended Fix Priority

### Phase 1: Bignum Foundation (HIGHEST IMPACT - could gain 100+ test cases)

1. **Fix bignum_value() helper** (1-2 hours)
   - Change from `100000 + plus` to actual heap integer allocation
   - Update rubyspec_helper.rb:534
   - Requires: Heap integer allocation to work correctly

2. **Fix multi-limb to_s** (2-4 hours)
   - Already mostly working according to docs/bignums.md
   - Fix remaining edge cases
   - Verify with to_s_spec.rb

3. **Fix heap integer comparison operators** (4-8 hours)
   - Rewrite `__cmp` dispatch system
   - Fix `<`, `>`, `<=`, `>=` for heap integers
   - Currently listed as "broken" in docs/bignums.md

**Expected Gain**: 80-120 passing test cases across 20+ spec files

### Phase 2: Type Coercion (HIGH IMPACT - could gain 50+ test cases)

1. **Add type checking to bitwise operators** (2-3 hours)
   - `&`, `|`, `^`, `~`, `<<`, `>>`
   - Check `is_a?(Integer)` before calling `__get_raw`
   - Print error and return nil instead of crashing

2. **Implement to_int coercion protocol** (3-4 hours)
   - Add `to_int` calls in operators before using arguments
   - Pattern already established in ceildiv

3. **Fix Mock object coercion** (1-2 hours)
   - Add proper to_int method to Mock
   - Remove __get_raw workaround

**Expected Gain**: 40-60 passing test cases across 15+ spec files

### Phase 3: Method Implementation (MEDIUM IMPACT - could gain 30+ test cases)

1. **Implement divmod** (2-3 hours)
   - Both for fixnums and heap integers
   - Fix divmod_spec.rb segfault

2. **Audit heap integer method return types** (2-4 hours)
   - Find methods returning nil when they should return objects
   - Fix multiply_spec.rb "NilClass#__multiply_heap_by_fixnum" error

3. **Fix arithmetic edge cases** (2-4 hours)
   - Negative shifts
   - Large shift amounts
   - Division by zero handling

**Expected Gain**: 30-50 passing test cases across 10+ spec files

### Phase 4: Float Support (LOWER PRIORITY - could gain 20+ test cases)

1. **Implement basic Float arithmetic** (4-6 hours)
2. **Fix to_f conversion** (1-2 hours)
3. **Float coercion protocol** (2-3 hours)

**Expected Gain**: 20-40 passing test cases across 5+ spec files

### Phase 5: Parser & Encoding (LOWEST PRIORITY)

1. **Stabby lambda support** - Complex parser work
2. **Full encoding implementation** - Large undertaking

## Test Case Count Enhancement

Current run_rubyspec only reports file-level pass/fail. Need to aggregate individual test case counts from successful runs.

**Implementation**:
1. Capture stdout from each spec run
2. Parse the summary line: "X passed, Y failed, Z skipped (N total)"
3. Aggregate across all specs
4. Report total individual test case counts

**Benefit**: Better visibility into actual progress (e.g., "150/500 test cases passing" vs "11/67 files passing")
