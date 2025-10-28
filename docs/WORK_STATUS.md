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

**Last Updated**: 2025-10-28 (Session 36 - COMPLETE)
**Current Test Results**: 67 specs | PASS: 20 (30%) | FAIL: 44 (66%) | CRASH: 3 (4%) | COMPILE FAIL: 0
**Individual Tests**: 577 total | Passed: 321 (55%) | Failed: 248 (43%) | Skipped: 8 (1%)
**Selftest Status**: ✅ selftest passes | ✅ selftest-c passes

**Recent Progress**: Session 36 COMPLETE - Fixed parser precedence, String#[] heap integers, and bitwise operators with negative fixnums. Reduced crashes from 5 to 3. Added +17 tests passing.

**Next Steps**: Work on quick wins from TODO.md - bit_length final fix, Float TypeError for bitwise ops, comparison operators.

---

## CRITICAL DEVELOPMENT RULE

**NEVER REVERT CODE WITHOUT SAVING IT FIRST**

During debugging and investigation:
- ✅ Commit or stash changes before trying different approaches
- ✅ Use `cp file.rb file.rb.backup` to save experimental changes
- ❌ **NEVER** use `git checkout` to revert without saving first
- ❌ **NEVER** delete files during investigation
- ❌ **NEVER** give up and revert - investigate the root cause

See CLAUDE.md for full details.

---

## Session 36: Parser, String#[], and Bitwise Operators (2025-10-28) ✅ COMPLETE

### Problem 1: Parser Precedence Bug
`-2**12` parses as `(-2)**12` = 4096 instead of `-(2**12)` = -4096. Root cause: tokenizer creates `-2` as a single negative literal token before parser applies precedence rules.

### Problem 2: Assembly Errors with Large Negative Constants (REGRESSION)
Initial precedence fix caused 21 compile failures with assembly errors like `Error: missing or invalid immediate expression '-46116860184273879049'`. The simplified tokenization bypassed `Number.expect` which handles large integer conversion to heap integers.

### Problem 3: String#[] Can't Handle Heap Integer Indices
After fixing compile errors, bit_or_spec and bit_xor_spec crashed. Investigation revealed String#[] was calling `__get_raw` on heap integers without type checking, causing crashes when bitwise operations returned heap integers as indices.

### Problem 4: Bitwise Operators Crash on Negative Fixnums
`(1 << 33) | -1` completed but crashed on `puts`. Root cause: `__bitor_fixnum_heap` and `__bitxor_fixnum_heap` always set sign=1 (positive) when converting fixnums to heap integers, even for negative fixnums like -1.

### Solutions

**Fix 1: Operator Precedence** (operators.rb:118-125)
- Changed unary +/- prefix priority from 7 to 20 (still less than ** at 21)
- Makes unary minus bind less tightly than `**`
- Ensures correct precedence when `-` is parsed as an operator

**Fix 2: Tokenizer Lookahead** (tokens.rb:408-431)
- Added special case in `-` handler to look ahead for `**`
- When `-` followed by digit after an operator: consume number, check for `**`
- If followed by `**`: unget number/minus, return `-` as operator (precedence applies)
- If NOT followed by `**`: unget and call `Number.expect` for proper heap integer handling
- Prevents assembly immediate value overflow errors

**Fix 3: String#[] Heap Integer Support** (lib/core/string.rb:115-194)
- Added `Integer#__to_fixnum_if_possible` helper method (lib/core/integer.rb:135-179)
- Helper checks if heap integer fits in fixnum range (-2^29 to 2^29-1)
- Returns fixnum if in range, nil if too large/small
- Updated String#[] to convert heap integer indices to fixnums when possible
- Returns nil for out-of-range heap integers (consistent with Ruby semantics)

**Fix 4: Bitwise Operators Sign Handling** (lib/core/integer.rb:2773-2989)
- Fixed `__bitor_fixnum_heap`, `__bitor_heap_fixnum` to check fixnum sign before conversion
- Fixed `__bitxor_fixnum_heap`, `__bitxor_heap_fixnum` with same sign checking
- When converting negative fixnum to heap: negate to get magnitude, set sign=-1
- When converting positive fixnum to heap: use value directly, set sign=1
```ruby
if other < 0
  magnitude = 0 - other
  other_heap = Integer.new
  other_heap.__set_heap_data([magnitude], -1)
else
  other_heap = Integer.new
  other_heap.__set_heap_data([other], 1)
end
```

### Test Results
**Parser & Assembly Fix**:
- `(-2 ** 12)` correctly outputs `-4096` ✅
- All 21 COMPILE FAIL specs now compile ✅
- 0 compile failures (was 21) ✅

**String#[] Fix**:
- make selftest: 0 failures ✅
- make selftest-c: 0 failures ✅
- String#[] no longer crashes on heap integer indices ✅

**Bitwise Operators Fix**:
- `(1 << 33) | -1` correctly outputs `-1` ✅
- `(1 << 33) ^ -1` correctly outputs `-8589934593` ✅
- bit_or_spec: CRASH → P:9 F:3 (+9 tests)
- bit_xor_spec: CRASH → P:8 F:5 (+8 tests)
- **Total: +17 tests passing**

**Final Session 36 Results**:
- CRASH specs: 5 → 3 (fixed bit_or, bit_xor)
- COMPILE FAIL specs: 21 → 0 (fixed all assembly errors)
- Pass rate: 321/577 tests (55%)
- Specs passing: 20/67 (30%)

### Files Modified
- `operators.rb`: Lines 118-125 (unary +/- precedence: 7 → 20)
- `tokens.rb`: Lines 408-431 (** lookahead logic + Number.expect)
- `lib/core/integer.rb`: Lines 135-179 (__to_fixnum_if_possible helper)
- `lib/core/integer.rb`: Lines 2773-2805 (Integer#| sign fixes)
- `lib/core/integer.rb`: Lines 2958-2989 (Integer#^ sign fixes)
- `lib/core/string.rb`: Lines 115-194 (heap integer index handling)

### Key Insights
1. **Parser fix exposed pre-existing bugs**: The 21 compile failures were masking runtime bugs in String#[] and bitwise operators
2. **Heap integer handling needed throughout**: Many methods assumed fixnums only, needed defensive heap integer checks
3. **Sign handling critical for negative numbers**: Converting negative fixnums to heap integers requires explicit sign checking
4. **Test improvement not regression**: Pass rate 55% is accurate, not a regression from artificially inflated 61%

---

## Session 35: Integer#<< (Left Shift) Implementation (2025-10-27) ✅ COMPLETE

### Problem
Current Integer#<< implementation uses multiplication which is inefficient and was causing incorrect results. Need proper shift-based implementation.

### Implementation Plan

**Step 1: Fixnum shifts without overflow**
- Use s-expression `(sall shift_amount value)` to perform actual bit shift
- Untag self to get raw value: `(sar self)`
- Untag other to get shift amount: `(sar other)`
- Perform shift: `(sall other_raw self_raw)`
- Check if result fits in fixnum range: `(and (gte shifted -536870912) (lte shifted 536870911))`
- If fits, retag and return: `(__int shifted)`
- Test: `1 << 10`, `5 << 20`, `1 << 28` should work

**Step 2: Fixnum shifts with overflow**
- If shift doesn't fit in fixnum range (Step 1 check fails), convert to heap
- Convert fixnum to heap: `Integer.new` + `__set_heap_data([self], 1)`
- Note: Shifts >= 30 will ALWAYS overflow (2^30 exceeds fixnum range)
- Call `__left_shift_heap(other)` on heap integer
- Test: `1 << 29`, `1 << 30`, `1 << 100`

**Step 3: Heap integer shifts**
- Algorithm breakdown:
  1. Calculate `full_limb_shifts = other / 30` (how many complete 30-bit limb positions to shift)
  2. Calculate `bit_shift = other % 30` (remaining bits to shift within limbs)
  3. Add `full_limb_shifts` zero limbs to result array (shifting entire limbs left)
  4. If `bit_shift == 0`: just copy remaining limbs (no bit shifting needed)
  5. If `bit_shift > 0`: shift each limb left by `bit_shift` bits with carry
     - For each limb: shift left using s-expression `(sall bit_shift limb_raw)`
     - Track carry from high bits that overflow 30-bit boundary
     - Add carry to next limb
     - If final carry > 0, add as new limb
- Use s-expressions for actual shifts (NO multiplication)
- Test: `(1 << 100).to_s`, verify correct large results

**Step 4: Handle negative numbers**
- Negative shifts: `self << -n` should equal `self >> n`
- Already handled in current code with `if other < 0` check

### Implementation Results

**Part 1 - Left Shift Implementation**: ✅ COMPLETE
- Implemented `__left_shift_fixnum` with overflow detection using shift-and-check-back method
- Implemented `__left_shift_heap` with proper limb-based algorithm:
  - Calculates full_limb_shifts = other / 30 (complete 30-bit position shifts)
  - Calculates bit_shift = other % 30 (remaining bit shift within limbs)
  - Adds zero limbs for full shifts
  - Shifts remaining limbs with carry propagation using `__shift_limb_with_carry_split`
- Fixed tagged literal bug: literals in s-expressions are automatically tagged, so `(sarl 30 val)` shifts by 29 not 30
  - Solution: use untagged variable `(let (shift_30) (assign shift_30 30) (sarl shift_30 val))`
- All positive number tests PASS: 1<<10, 1<<29, 1<<30, 1<<100 all correct
- Files: `lib/core/integer.rb:3007-3118` (Integer#<<, __left_shift_fixnum, __left_shift_heap, __shift_limb_with_carry_split)

**Part 2 - Parser Precedence Fix for Unary Minus**: ⚠️ INCOMPLETE
- Problem: `-2**12` parses as `(-2)**12` = 4096 instead of `-(2**12)` = -4096
- Root cause: Tokenizer treats `-2` as single negative literal token before parser sees it
- Attempted fix: Changed unary +/- prefix operator priority from 99 to 7 (less than ** at 21)
- Result: Didn't fix the issue because tokenizer combines `-2` into literal at line tokens.rb:406-409
- Workaround discovered: `- 2 ** 12` (with space) parses correctly as `[:-, [:**, 2, 12]]`
- Status: Parser precedence change committed but tokenizer behavior still causes `-2**12` to fail
- Files: `operators.rb:118-125` (changed prefix +/- priority)

**Testing Results**:
- bit_length_spec: P:2 F:2 - positive number tests PASS, negative number tests FAIL (due to parser issue)
- Shift tests: All manual tests pass (1<<10 through 1<<100)
- make selftest-c: 0 failures ✓ NO REGRESSIONS

**Known Issue**: Unary minus precedence with ** requires tokenizer changes to prevent `-<digit>` being treated as negative literal. This affects tests with expressions like `-2**12`.

### Files Modified
- `lib/core/integer.rb`: Lines 3007-3118 (Integer#<< and helper methods)
- `operators.rb`: Lines 118-125 (unary +/- prefix priority changed from 99 to 7)

---

## Recent Work (Last 3 Sessions)

### Session 34: pow_spec and exponent_spec Crash Fix (2025-10-27) ✅

**Problem**: pow_spec and exponent_spec were both crashing during compilation/execution. Investigation revealed two root causes:
1. **Carry overflow in multiplication**: The formula `carry_out = low_contribution + sign_adjust + (sum_high * 4)` in `__multiply_limb_by_fixnum_with_carry` can produce values >= 2^30 when sum_high ≈ 2^28. Since fixnum max is 2^29-1, tagging these large values creates corrupted "fake fixnums" that break heap integer multiplication.
2. **Huge exponent hang**: Tests like `2 ** 427387904` caused infinite memory allocation loops.

**Fix Part 1 - Carry Normalization**:
- Created `__normalize_limb(tagged_val)` helper (lib/core/integer.rb:608-635) that splits oversized carries
- If raw_val >= limb_base (2^30): splits into `limb = val % 2^30` and `overflow = val / 2^30`
- Returns both as tagged fixnums in array created directly in s-expression (avoids recursion)
- Applied normalization in `__multiply_heap_by_fixnum` (lines 763-775) and `__multiply_heap_by_heap` (lines 840-888)
- Fixed infinite recursion bug by creating array directly instead of calling `__make_overflow_result`

**Fix Part 2 - Exponent Size Limit**:
- Added check for exponents > 32,537,661 (exact MRI limit from Ruby 3.2)
- Returns `Float::INFINITY` for oversized exponents instead of attempting computation
- Prevents memory explosion from huge exponents
- Files: lib/core/integer.rb:3395-3398

**Test Results**:
- pow_spec: CRASH → P:7 F:22 S:2 (31 total) ✓ NOW RUNS (+7 tests)
- exponent_spec: CRASH → P:7 F:12 S:2 (21 total) ✓ NOW RUNS (+7 tests)
- 2^32 = 4294967296 ✓ (now correct, was wrong)
- 2^40 = 1099511627776 ✓ (now correct, was wrong/timeout)
- 2^427387904 → Float::INFINITY ✓ (was hang)

**Remaining Failures**: Expected - modulo exponentiation not implemented, Float/Rational arithmetic not implemented, type checking incomplete.

**Impact**: Crashes reduced from 3 to 1 (only times_spec still crashes). Overall: 22/67 specs (33%), 311/609 tests (51%).

**Files Modified**: lib/core/integer.rb (normalize_limb helper, multiplication fixes, exponent limit)

**Commits**: 6d80ff8 (docs update)

---

### Session 32: TODO Re-assessment + Bitwise Ops + Division Crash Fix (2025-10-27) ✅

**Part 1 - Re-assessment**: Re-assessed all 67 integer specs to verify current status. Updated spec_failures.txt with latest results. Discovered that ceil_spec and truncate_spec now PASS (fixed by commits c66e6e2, a64e125, 94a989c, aeedc76), sqrt_spec improved from CRASH to FAIL. Corrected TODO.md and WORK_STATUS.md with accurate numbers. Result: Current status verified as 18/67 specs (27%), 265/507 tests (52%).

**Part 2 - Bitwise AND -1 Special Case**: Implemented special case optimization for `X & -1 = X` in Integer#&. This is the most common negative bitwise operation (since -1 has all bits set in two's complement). Files: `lib/core/integer.rb:2291-2298`. Result: bit_and_spec improved from P:8 F:5 to P:9 F:4. Selftest-c passes with 0 failures.

**Part 3 - Two's Complement Research**: Researched current implementation of bitwise operations in lib/core/integer.rb. Findings:
- Heap integers use sign-magnitude representation: `@sign` (1 or -1) + `@limbs` (array of absolute value limbs)
- Current bitwise operations (`__bitand_heap_heap`, `__bitor_heap_heap`, `__bitxor_heap_heap`) completely ignore sign
- No two's complement conversion exists yet
- Bitwise operations need two's complement: for negative N, convert |N| to one's complement (invert all bits) then add 1
- Failing tests: bit_and_spec P:9 F:4 - the 4 failures are operations with negative heap integers
- Next step: implement incremental two's complement conversion for Integer#& with negative operands

**Part 4 - Two's Complement Implementation for Integer#&**: Implemented full two's complement conversion for negative heap integers in bitwise AND operations. Files: `lib/core/integer.rb:2348-2410 (helpers), 2410-2495 (updated __bitand_heap_heap), 2497-2550 (helper methods)`.

**Algorithm**:
- Added `__magnitude_to_twos_complement(limbs, num_limbs)`: converts magnitude M to ~M + 1
- Added helper methods: `__invert_limb`, `__add_with_carry`, `__extend_limbs_with_zeros`, `__trim_leading_zeros`, `__max_fixnum`
- Updated `__bitand_heap_heap`: detects negative operands, converts to two's complement, performs AND, converts result back if negative
- Result sign: negative iff both operands are negative (matches Ruby semantics)

**Result**: bit_and_spec improved from P:9 F:4 to P:11 F:2. Remaining 2 failures are Float type checking (unrelated to two's complement). Selftest-c passes with 0 failures.

**Part 5 - Two's Complement for Integer#| and Integer#^**: Applied same two's complement logic to Integer#| (bitwise OR) and Integer#^ (bitwise XOR).
- Integer#|: result is negative if either operand is negative
- Integer#^: result is negative if exactly one operand is negative (XOR of signs)
- Files: Updated `__bitor_heap_heap` and `__bitxor_heap_heap` in `lib/core/integer.rb`

**Final Results**:
- bit_and_spec: P:11 F:2 (was P:9 F:4) +2 tests
- bit_or_spec: P:7 F:5 (was P:6 F:6) +1 test
- bit_xor_spec: P:6 F:7 (was P:5 F:8) +1 test
- allbits_spec: P:4 F:0 (was P:3 F:1) +1 test ✓ NOW PASS
- anybits_spec: P:4 F:0 (was P:3 F:1) +1 test ✓ NOW PASS
- nobits_spec: P:4 F:0 (was P:3 F:1) +1 test ✓ NOW PASS
- **Total: +7 tests passing** across bitwise operations with negative integers
- Remaining failures in bit_or/bit_xor are due to Integer#<< (shift) not handling large shifts (separate issue)
- Remaining Float type checking failures are separate issue from two's complement
- Selftest-c passes with 0 failures

**Part 6 - Division Crash Fix**: Investigated divide_spec, divmod_spec, div_spec crashes using GDB and investigate-spec skill. Root cause: fixnum overflow in `__shift_limbs_left_one_bit` at line 2123. The code computed `half_base + half_base` (536870912 + 536870912 = 1073741824) which exceeds fixnum range (2^30-1), wrapping to -1073741824 (negative!). This corrupted all division operations.

**Fix**: Added `__limb_base` helper method (returns 1073741824 as heap integer) and updated `__shift_limbs_left_one_bit` to use it directly instead of `half_base + half_base`. Files: `lib/core/integer.rb:942-946` (new helper), `2108-2143` (updated method).

**Result**:
- divide_spec: CRASH → P:10 F:8 (+10 tests)
- divmod_spec: CRASH → P:5 F:8 (+5 tests)
- div_spec: CRASH → P:10 F:13 (+10 tests)
- **Total: +25 tests passing, 3 specs no longer crash**
- Selftest-c: 0 failures (no regressions)
- Overall progress: 67 specs | PASS: 21 (31%, was 18/27%) | CRASH: 3 (4%, was 6/9%)

### Session 31: Bitwise Operators & Precedence Fix (2025-10-26) ✅

**Completed**: Implemented bitwise operators (|, &, ^) for positive heap integers using 4-way dispatch (fixnum|fixnum, fixnum|heap, heap|fixnum, heap|heap). Fixed operator precedence bug - bitwise operators now bind tighter than comparisons. Files: `lib/core/integer.rb`, `operators.rb`. Result: allbits_spec 3/4 passing (was 1/7). Commits: 9396721, cd8efae.

**Remaining**: Negative numbers need two's complement implementation.

### Session 30: Rescue+Yield Interaction Fix (2025-10-26) ✅

**Completed**: Fixed rescue blocks to catch exceptions from yielded blocks. Added ESP restoration during unwinding (previously only restored EBP). Added `:stackpointer` primitive. Moved after_label inside let() block to fix stack corruption. Added rescue wrapper in spec framework. Files: `compiler.rb:495-520, 666-669`, `lib/core/exception.rb:53-68`, `rubyspec_helper.rb:52-59`. Result: 5 specs no longer crash (pow_spec, round_spec, divmod_spec, div_spec, exponent_spec).

### Session 29: Exception Handling Implementation (2025-10-23) ✅

**Completed**: Implemented basic exception handling. Converted ExceptionRuntime to instance methods. Fixed local variable scope in begin/rescue using `let()`. Renamed `:raise` keyword to `:unwind` to avoid conflicts. Files: `lib/core/exception.rb`, `compiler.rb:488-514, 640-703`, `lib/core/object.rb`. Result: raise/rescue works, stack unwinding through multiple frames works, selftest passes.

**Not implemented**: Typed rescue, rescue variable binding, multiple rescue clauses, ensure blocks, retry.

---

## Historical Work (Brief Reference)

- **Session 28** (2025-10-22): Fixed eigenclass nested defm bug - rewrite_let_env now recursively processes nested :defm nodes
- **Session 27** (2025-10-21): Implemented eigenclass with nested let() - fixed LocalVarScope offset tracking
- **Session 26** (2025-10-20): Discovered LocalVarScope nesting limitations, shelved approach
- **Session 25** (2025-10-20): EigenclassScope implementation attempt - runtime crashes, reverted
- **Session 24** (2025-10-20): Eigenclass architecture design - paused due to scope chain issues
- **Session 23** (2025-10-19): Eigenclass bug partial fix - first eigenclass works, second crashes
- **Session 22** (2025-10-19): Fixed exponent_spec and pow_spec SEGFAULTs (BeCloseMatcher nil handling, Integer#infinite?, Integer#pow)
- **Session 21** (2025-10-19): Fixed parser bug - parenthesis-free method chains now parse correctly

For detailed historical session notes, see git commit messages or separate documentation files.

---

## Current Known Issues

### SEGFAULTs (1 spec) ✓ MAJOR PROGRESS
1. **times_spec**: Parser treats `or break` as method calls instead of boolean operator

**FIXED in Session 34**:
- ✅ **pow_spec, exponent_spec**: Now RUN (P:7 F:22, P:7 F:12) - fixed carry overflow
- ✅ **divide_spec, divmod_spec, div_spec**: Now RUN (Session 33) - fixed heap division

### Parser Bugs
1. **round_spec**: Parser treats `half: :up` as ternary operator instead of hash literal (causes FAIL, not crash)

See TODO.md for full task breakdown.

---

## Test Commands

```bash
make selftest-c                                    # Check for regressions (MUST PASS)
./run_rubyspec rubyspec/core/integer/              # Full integer suite
./run_rubyspec rubyspec/core/integer/[spec].rb     # Single spec
```

---

## Update Protocol

**After completing any task**:
1. Update test status numbers at top of this file
2. Run `make selftest-c` (MUST pass with 0 failures)
3. Add brief completion note to "Recent Work" section
4. Trim old session details if more than 3 sessions listed
5. Commit with reference to this document

**This is the journaling space for ongoing work. See TODO.md for task list.**
