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

**Last Updated**: 2025-11-01 (Session 41 - Language Spec Compilation Error Fixes)
**Current Test Results**: 30/67 specs (45%), 372/594 tests (62%), 3 crashes
**Selftest Status**: 0 failures ✅

**Recent Progress**:
- Session 40: Fixed `__cmp_heap_fixnum` in pure Ruby
- Session 41 (initial): Fixed Mock#stub!, `__cmp_fixnum_heap`, +9 tests
- Session 41 (continued): Fixed duplicate method bug, bit_or and bit_xor now 100% passing
- Session 41 (Float investigation): Investigated Float implementation requirements (documented, deferred)
- Session 41 (Integer#>> implementation): Implemented right shift for heap integers (+14 tests)
- Session 41 (regression fix): Fixed element_reference_spec crash with 2^24 shift limit
- Session 41 (sqrt optimization): Applied >> 1 optimization (+18 tests)
- Session 41 (integer_spec): Added integer? method, attempted include Comparable
- Session 41 (language spec analysis): Analyzed 17 language specs, categorized 9 error types
- Session 41 (error reporting): ✅ Fixed Scanner#position=, ✅ Shunting yard errors, ✅ Parser errors

**Achievements**:
- ✅ Completed BUG 1 (Integer#>>)! right_shift_spec +14 tests, left_shift_spec +3 tests
- ✅ Completed language spec compilation error analysis
- ✅ Fixed Scanner#position= parser bug (commit f541211)
- ✅ Improved shunting yard error reporting with human-readable messages + debug mode (commit 33914d0)
- ✅ Improved parser error reporting with line:column format + debug mode (commit 8a9e418)
- ✅ Added begin/rescue/else clause support (commit c2c20da)

**Next Steps**:
1. Fix highest-frequency compilation errors (Expected EOF, do..end block, missing ')'/missing 'end')
2. Consider shunting yard errors for "Method call requires two values"
3. Continue with lower-frequency parser bugs

---

## Session 41 (final): Error Frequency Analysis Complete (2025-11-02) ✅ COMPLETE

**Completed Tasks**:
1. ✅ Removed `include` as keyword, implemented as method (commit 815ada4)
   - Allows `.include?` method calls to work
   - Preserves compile-time module inclusion via special handling in compile_calls.rb
2. ✅ Created analyze_all_language_errors.rb script (commit 83aebaf)
3. ✅ Ran full error frequency analysis on all 79 language specs
4. ✅ Documented actual error patterns and frequencies

**Error Frequency Analysis Results**:
- 79 total language specs analyzed
- ~20 specs appear to compile/run successfully (show only debug output in error capture)
- ~47 specs have compilation errors with clear patterns

**Top 5 Compilation Errors** (by frequency):
1. Expected EOF - 6 specs
2. Method call requires two values (:should) - 5 specs (shunting yard)
3. Expected: do .. end block - 5 specs
4. Expected: ')' - 4 specs
5. Expected: 'end' for 'do'-block - 4 specs

**Files Created/Modified**:
- analyze_all_language_errors.rb - Full error analysis script
- language_spec_error_analysis_correct.txt - Complete analysis output
- docs/TODO.md - Updated with actual error frequencies
- docs/WORK_STATUS.md - This file

**Commits**:
- 20d7d49: Document language spec priority list failure
- 815ada4: Remove 'include' as keyword, implement as method
- 83aebaf: Fix analyze_all_language_errors.rb to run actual specs
- 7419fd4: Correct TODO.md with accurate language spec status

---

## Session 41 (continued): Language Spec Priority Re-evaluation (2025-11-01) ✅ COMPLETE

### Problem Statement
After implementing begin/ensure blocks (commit 8bf7f18) and bare splat operator (commit 6d1dce2), language spec compilation failures only decreased by 1 (72 → 71), with one regression (safe_spec crash→fail). This indicates the priority list in LANGUAGE_SPEC_COMPILATION_ERRORS.md was not focused on high-impact fixes.

### Root Cause Analysis

**The Priority List Was Wrong**:
- Original analysis sampled only 17 specs out of 72 failing ones
- Priorities based on manual code inspection, NOT actual error frequency
- Items #1-6 implemented (Scanner#position=, begin/rescue/ensure, bare splat) had minimal impact

**Discovery Process**:
1. Attempted to analyze errors by compiling specs directly → ALL failed with "Unable to open 'mspec'" error
2. Discovered `run_rubyspec` script bypasses mspec by:
   - Creating temporary spec files
   - Replacing `require_relative 'spec_helper'` with `require 'rubyspec_helper'`
   - Filtering out all require_relative lines
   - Inlining fixtures and shared files
3. Analyzed preprocessed temp files to find ACTUAL compilation errors

**Actual Error Examples Found**:
- `alias_spec`: "Expected: name of module to include" - parser treats `.should include(:foo)` as `include ModuleName` keyword
- `and_spec`: "Expected an argument on left hand side of assignment" - multiple assignment not supported
- `array_spec`: **COMPILES SUCCESSFULLY** (one of the specs actually works!)
- `case_spec`: "Method call requires two values" - shunting yard expression parsing error

### Key Insight: `include` Keyword Ambiguity

**The Issue**: Parser has `include` in Keywords set (tokens.rb:7), so it treats method calls like `.should include(:foo)` as the `include ModuleName` statement.

**Proposed Solution** (suggested by user):
- Remove `include` from Keywords set
- Implement `include` as a method on Class/Module instead
- This should be relatively easy and may unblock multiple specs

### Next Steps
1. ✅ Document findings in TODO.md and WORK_STATUS.md
2. [ ] Run full error frequency analysis on all 72 language spec temp files
3. [ ] Categorize errors and count frequencies
4. [ ] Create new data-driven priority list
5. [ ] Fix highest-frequency error (adjusted by ease) - likely `include` keyword ambiguity

### Files Modified
- docs/TODO.md: Added critical lesson learned warning
- docs/WORK_STATUS.md: This section

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

## Session 41 (Continued): Critical Fixnum MAX and Overflow Fixes (2025-10-31 to 2025-11-01) ✅ COMPLETE

### Problem Discovery

**User Insight**: "If the framework shows the same number twice, then that suggests a comparison bug."

Investigation revealed bit_or was producing CORRECT numerical values, but comparison was failing!
- Test: `18446744073709551627 | -0x40000000000000000`
- Result: `-55340232221128654837` ✓
- Expected: `-55340232221128654837` ✓
- But: `result == expected` returned FALSE ❌

###Root Cause Found

Heap integers created by bit_or had **NEGATIVE LIMBS** (e.g., `limbs: [-11, 0, 48]`), violating the invariant that limbs must be positive [0, 2^30-1]. This broke all comparison logic.

**Why negative limbs?**
- Fixnum MAX was set to 2^29-1 (536870911)
- But limbs are 30-bit values up to 2^30-1 (1073741823)
- Since limbs MUST be tagged fixnums, values > 536870911 overflowed and created negative values!

**Critical Revelation (from user)**:
- "Limbs ARE 30 bits"
- "There is NO SCENARIO where it is acceptable for a limb to be ANYTHING OTHER THAN A TAGGED fixnum"
- "There is 1 tag bit, and 31 bits for storing the values and sign"

### Solution

**Fix fixnum range to support 30-bit limbs:**

With 32-bit integers:
- 1 bit for tag (bit 0)
- 31 bits for signed value (bits 1-31)
- Signed 31-bit range: [-2^30, 2^30-1] = [-1,073,741,824, 1,073,741,823]

**Changes Made:**
1. `integer_base.rb` and `integer.rb`:
   - MAX: 536870911 → **1073741823** (2^30-1)
   - MIN: -536870912 → **-1073741824** (-2^30)

2. Reverted temporary fixes in `integer.rb`:
   - `__limb_base_minus_one`: Restored to 1073741823 (was temporarily 536870911)
   - `__subtract_one_magnitude`: Restored borrow value to 1073741823

### Results

✅ **Selftest**: 0 failures (still passing)
✅ **bit_or operation**: Now produces correct numerical values
✅ **limb_base_minus_one**: Now valid (1073741823 fits in fixnum MAX)
⚠️ **Remaining issue**: Internal representation still has negative limbs - needs investigation

### Files Modified
- `lib/core/integer_base.rb`: MAX/MIN constants
- `lib/core/integer.rb`: MAX/MIN constants, comments, limb constants

### Commits
- 3654329: Fix __cmp_heap_heap using pure Ruby comparisons
- e05cfe2: Fix fixnum MAX to 2^30-1 for 30-bit limb support

### 32-Bit Overflow Fix (2025-11-01)

**Problem**: When adding limb (1073741823) + carry (1):
- Tagged values: 2147483647 + 3 = 2147483650
- Exceeds 32-bit signed max (2147483647)
- Wraps to negative, creating negative limbs in result

**Error Encountered**: "wrong number of arguments (given 3, expected 2)"
- Root cause: Two definitions of `__add_limbs_with_carry` with different signatures
- Old version: `(a, b, c)` - returns raw sum value
- New version: `(a, b)` - returns [limb, carry] array

**Solution**: Renamed new method to `__add_two_limbs_with_overflow(a, b)`
- Uses raw arithmetic in s-expression to avoid tagged overflow
- Returns [result_limb, carry] where result_limb < 2^30
- Properly handles limb_base = 2^30 (1073741824) by untagging literal

**Implementation** (lib/core/integer.rb:2601-2620):
```ruby
def __add_two_limbs_with_overflow(a, b)
  %s(
    (let (a_raw b_raw sum limb_base_tagged limb_base result_limb carry_out)
      (assign a_raw (sar a))
      (assign b_raw (sar b))
      (assign sum (add a_raw b_raw))
      (assign limb_base_tagged 1073741824)
      (assign limb_base (sar limb_base_tagged))  # Untag to get raw 2^30
      (if (ge sum limb_base)
        (do
          (assign result_limb (sub sum limb_base))
          (assign carry_out 1))
        (do
          (assign result_limb sum)
          (assign carry_out 0)))
      (return (array (__int result_limb) (__int carry_out))))
  )
end
```

**Used by**: `__add_one_magnitude` (line 2630)

### Final Results

✅ **Selftest**: 0 failures (no regressions)
✅ **Overall**: 352/583 tests (60%), +3 from baseline 349
✅ **Specs**: 28/67 (42%), same as baseline
✅ **Crashes**: 3 (same as baseline - fdiv, round, times)

**Improvements**:
- bit_or_spec: Now functional (P:11 F:1)
- bit_xor_spec: Now functional (P:11 F:2)
- Limbs are now positive values [0, 2^30-1] ✓
- Comparisons work correctly ✓
- No 32-bit overflow in limb addition ✓

**Remaining Issues**:
- Some bitwise operations produce numerically incorrect results (limbs appear half expected value)
- Issue is in bitwise logic, not in addition/comparison

### Files Modified
- `lib/core/integer_base.rb`: MAX/MIN constants (2^30-1, -2^30)
- `lib/core/integer.rb`:
  - MAX/MIN constants
  - `__cmp_heap_heap`: Pure Ruby comparisons
  - `__add_two_limbs_with_overflow`: New overflow-safe limb addition
  - `__add_one_magnitude`: Uses new overflow-safe method

### Duplicate Method Bug Fix (2025-11-01) ✅ COMPLETE

**Problem**: Commit d4a9abe accidentally created TWO definitions of `__add_two_limbs_with_overflow`
- First definition (line 2238): CORRECT - uses `__limb_base_raw`
- Second definition (line 2601): BUGGY - tried to use literal 1073741824
- Ruby uses the last definition, so the buggy one was active

**Why the literal approach failed**:
- Literal `1073741824` (2^30) in s-expression gets auto-tagged: `(1073741824 << 1) | 1`
- But `1073741824 << 1 = -2147483648` (32-bit signed overflow to negative!)
- Untagging with `sar` (arithmetic right shift): `-2147483648 >> 1 = -1073741824`
- Wrong limb_base value caused incorrect overflow detection
- Result: limb values were roughly half what they should be

**The Correct Solution** (`__limb_base_raw`):
```ruby
def __limb_base_raw
  %s(
    (let (k1 k2 result)
      (assign k1 1024)
      (assign k2 (mul k1 k1))  # 1024 * 1024 = 1048576
      (assign result (mul k2 k1))  # 1048576 * 1024 = 1073741824
      (return result))  # Return RAW, don't tag!
  )
end
```

Computes 2^30 as `1024 * 1024 * 1024` in RAW (untagged) form, completely avoiding overflow.

**Fix**: Removed duplicate buggy definition (lines 2598-2619)

**Results**:
- ✅ bit_or_spec: P:12 F:0 (100% PASSING, was P:11 F:1)
- ✅ bit_xor_spec: P:13 F:0 (100% PASSING, was P:11 F:2)
- ✅ Overall: 30/67 specs (45%, +2), 354/583 tests (60%, +2)
- ✅ Selftest: 0 failures

### Commits
- 3654329: Fix __cmp_heap_heap using pure Ruby comparisons
- e05cfe2: Fix fixnum MAX to 2^30-1 for 30-bit limb support
- d4a9abe: Fix 32-bit overflow in limb addition (introduced duplicate bug)
- 9705019: Remove duplicate buggy __add_two_limbs_with_overflow

### Float Implementation Investigation (2025-11-01) 📋 DOCUMENTED

**Task**: Investigate minimal "Fake Float" implementation to unlock Float-related test failures

**Findings**:

1. **Compiler's Float Handling is Low-Level**:
   - `compiler.rb:137-147` shows Float literals are handled at assembly level
   - Tokenizer parses float literals (e.g., "4.999") and calls `.to_f` (MRI Ruby Float)
   - Compiler generates code: `Float.new()` with NO arguments, then uses `storedouble` instruction
   - `storedouble` writes double value directly to memory at offset 4 in Float object

2. **Incompatibility with Ruby-Based Approach**:
   - Attempted to implement Float using `@value` instance variable to store integer approximation
   - But compiler expects C-style memory layout: double at fixed offset 4
   - Instance variable storage doesn't match offset 4 memory layout
   - This caused lte_spec to crash (was P:5 F:2, became SEGFAULT)

3. **Original Float.rb Design**:
   - Uses `@value_low` and `@value_high` to reserve space for 8-byte double (2 x 32-bit)
   - Compiler writes double value directly to this space via `storedouble`
   - Float methods are stubs that return `self`, `false`, or `0`

**Conclusion**:
- "Fake Float" approach incompatible with compiler's low-level Float handling
- Proper Float implementation requires either:
  - Changing compiler's Float instantiation (compiler.rb:137-147)
  - OR implementing real Float arithmetic with proper memory layout
- Decision: DEFER Float work in favor of non-Float Priority 1 specs

**Files Investigated**:
- `lib/core/float.rb`: Float class implementation
- `tokens.rb:205-241`: Float literal parsing
- `compiler.rb:137-147`: Float constant code generation

**Status**: Investigation complete, Float work deferred, reverted to baseline

### Integer#>> Implementation (2025-11-01) ✅ COMPLETE

**Task**: Implement Integer#>> (right shift) for heap integers (BUG 1, estimated 4-6 hours)

**Implementation** (lib/core/integer.rb:3291-3445):

1. **Main method** (`>>`, lines 3291-3327):
   - Type conversion for `other`
   - Handle negative shifts: `if other < 0; return self << (-other); end`
   - Handle zero and large shift edge cases
   - Dispatch to fixnum or heap implementation

2. **Fixnum implementation** (`__right_shift_fixnum`, lines 3329-3350):
   - Handle shifts >= 31: return 0 (positive) or -1 (negative)
   - Otherwise use arithmetic right shift (`sarl`)
   - Fixes x86 shift-modulo-32 issue

3. **Heap implementation** (`__right_shift_heap`, lines 3352-3420):
   - Calculate full_limb_shifts = other / 30 (complete limbs to remove)
   - Calculate bit_shift = other % 30 (remaining bit shift)
   - Remove full limbs from right (least significant)
   - Shift remaining limbs with borrow from next limb
   - Handle sign extension for negative numbers

4. **Helper method** (`__shift_limb_right_with_borrow`, lines 3422-3445):
   - Shift current limb right, OR in high bits from next limb
   - Uses s-expression for raw arithmetic
   - Returns array with result limb

**Test Results**:
- ✅ Fixnum right shift: All basic tests pass
- ✅ Heap right shift: Large shifts work correctly
- ✅ Negative shifts: Correctly delegate to left shift
- ✅ Sign extension: Negative numbers return -1 when shifted away

**RubySpec Results**:
- right_shift_spec: P:16 F:19 → P:30 F:8 (+14 tests, 79% pass rate)
- left_shift_spec: P:27 F:7 → P:30 F:8 (+3 tests, benefits from >> in << -n)
- Remaining 8 failures each: edge cases with very large shifts (> 2^32)
- Overall pass rate: 60% → 63% (+3 percentage points)

**Status**: BUG 1 FIXED ✅, selftest passes with 0 failures

### Files Modified
- `lib/core/integer.rb`: Added Integer#>>, __right_shift_fixnum, __right_shift_heap, __shift_limb_right_with_borrow

### Commit
- eb53140: Implement Integer#>> (right shift) for heap integers

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

## Session 41 (continued): Language Spec Compilation Error Analysis (2025-11-01) ✅ COMPLETE

### Task
Analyze compilation failures in rubyspec/language/ specs to categorize error types and prioritize fixes.

### Approach
1. Sampled 17 specs across all 6 categories from LANGUAGE_SPEC_ANALYSIS.md
2. Documented actual compilation errors with context
3. Categorized errors by root cause and fix complexity
4. Prioritized fixes by impact and difficulty

### Specs Analyzed
**Category 1 - Core Language Features**: if_spec, case_spec, def_spec, block_spec, class_spec, loop_spec, lambda_spec
**Category 2 - Control Flow**: break_spec, return_spec
**Category 3 - Exception Handling**: ensure_spec, rescue_spec
**Category 4 - Advanced Features**: and_spec, or_spec, keyword_arguments_spec
**Category 5 - String/Regex Features**: heredoc_spec, hash_spec, string_spec

### Key Findings

**CRITICAL: Parser Bug Discovered** 🐛
- Error: `undefined method 'position=' for #<Scanner:...>`
- Affected: break_spec, string_spec, and likely 5-10 more specs
- Root cause: parser.rb:405 calls `scanner.position = ...` but Scanner only has `position` getter, not setter
- **Impact**: Actual compiler bug blocking many specs
- **Priority**: HIGHEST - fixing this may unblock many specs immediately
- **Complexity**: LOW - just add setter method

### Error Categories Identified

1. **Parser Internal Bug** (CRITICAL) - Scanner#position= missing
2. **Argument Parsing** (HIGH) - Splat/keyword arguments not supported
3. **Begin/Rescue/Ensure** (HIGH) - Missing else/ensure support
4. **Shunting Yard Errors** (MEDIUM-HIGH) - Expression parsing issues
5. **Multiple Assignment** (MEDIUM) - Destructuring not supported
6. **Lambda Brace Syntax** (MEDIUM) - Only do..end supported
7. **Heredoc Parsing** (LOW-MEDIUM) - Various heredoc issues
8. **String/Symbol Parsing** (LOW-MEDIUM) - Edge cases
9. **Link Failures** (LOW) - Missing exception classes (NameError)

### Documentation Created

**LANGUAGE_SPEC_COMPILATION_ERRORS.md**:
- 9 error categories with examples
- Affected specs for each category
- Root cause analysis
- Fix complexity estimates
- Recommended fix order (4 phases)
- Error reporting improvement suggestions

### Recommended Action Plan (from docs)

**Phase 1**: Fix Scanner#position= bug - may unblock 5-10 specs
**Phase 2**: Add else/ensure to begin/rescue parser
**Phase 3**: Support splat/keyword arguments
**Phase 4**: Fix shunting yard errors incrementally

**Before ALL fixes**: Improve error reporting to make parser errors more helpful

### Results
- ✅ Comprehensive error categorization complete
- ✅ Critical parser bug identified (Scanner#position=)
- ✅ Fix priorities established
- ✅ Documentation complete and linked from TODO.md

### Files Created/Modified
- `docs/LANGUAGE_SPEC_COMPILATION_ERRORS.md` - **NEW** comprehensive analysis
- `docs/TODO.md` - Updated with error categories and action plan
- `docs/WORK_STATUS.md` - This session documentation

### Next Steps
1. **Fix Scanner#position= bug** (highest priority, quick win)
2. **Or** continue with integer spec improvements
3. **Or** work on power/multiplication accuracy bug (BUG 2)

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
