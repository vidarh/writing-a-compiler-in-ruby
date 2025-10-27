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

**Last Updated**: 2025-10-27 (Session 34)
**Current Test Results**: 67 specs | PASS: 22 (33%) | FAIL: 44 (66%) | CRASH: 1 (1%)
**Individual Tests**: 609 total | Passed: 311 (51%) | Failed: 289 (47%) | Skipped: 9 (1%)
**Selftest Status**: ✅ selftest passes | ✅ selftest-c passes

**Recent Progress**: Fixed carry overflow in heap integer multiplication! pow_spec and exponent_spec now RUN instead of crashing. Added +14 passing tests from pow/exponent operations.

**Next Steps**: Parser bugs (times_spec crash, round_spec failures) or shift operators for heap integers.

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
