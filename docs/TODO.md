# Ruby Compiler TODO

**Purpose**: Task list for improving rubyspec test pass rate (integer specs + language specs)
**Format**: One-line tasks. Details in referenced docs.

**Current Status (Session 42)**:
- **Integer specs**: 30/67 passing (45%), 372/594 tests (62%), 3 crashes
- **Language specs**: Re-running after fixes (awaiting updated results)
- **Recent fixes** (Session 42):
  - Split precedence for assignment operators (fixes `true && x = 1` parsing)
  - Empty parentheses now evaluate as nil (fixes `() && true` and similar expressions)
  - Added 'not' keyword operator (improves not_spec from 4/16 to 9/10 tests)
  - Destructuring assignment now calls to_a (fixes `x, y = nil` - and_spec now 10/10 tests)

**For details**: See [RUBYSPEC_STATUS.md](RUBYSPEC_STATUS.md)
**For ongoing work**: See [WORK_STATUS.md](WORK_STATUS.md) (journaling space)
**For debugging**: See [DEBUGGING_GUIDE.md](DEBUGGING_GUIDE.md)
**For language spec errors**: See [LANGUAGE_SPEC_COMPILATION_ERRORS.md](LANGUAGE_SPEC_COMPILATION_ERRORS.md)

**⚠️ CRITICAL LESSON LEARNED (Session 41)**: The language spec priority list in LANGUAGE_SPEC_COMPILATION_ERRORS.md was based on a 17-spec sample and manual code inspection, NOT actual error frequency analysis. After implementing items #1-6 (Scanner#position=, begin/rescue/ensure, bare splat), only 1 compilation failure was reduced (72 → 71). **Always validate priorities with data-driven analysis before implementing fixes.**

**⚠️ SECOND CRITICAL ERROR (Session 41)**: Initial "data-driven" analysis incorrectly analyzed temp files from BOTH integer and language specs, giving completely wrong numbers (claimed 87/145 specs compile when reality is ~4%). **Always verify you're analyzing the correct data set.**

**✅ COMPLETE (Session 41)**:
- Created analyze_all_language_errors.rb and ran full error frequency analysis
- **Actual Results**: 79 language specs analyzed
  - ~20 specs appear to compile/run (show only debug output in error capture)
  - ~47 specs have actual compilation errors
  - 0 specs fully pass all tests

**⚠️ IMPORTANT**: Some spec compilation errors are caused by the `run_rubyspec` script's sed transformations mangling valid Ruby code. See [rubyspec_runner_limitations.md](rubyspec_runner_limitations.md) for details. The `it_behaves_like` parenthesization breaks multi-line lambda blocks.

## 🐛 KNOWN BUGS

### Integer::MIN Literal Causes selftest-c Assembly Failure
**Status**: WORKAROUND IN PLACE (Integer::MIN commented out)
**Discovered**: Nov 3, 2025 (Session 42)

**Problem**: Defining `Integer::MIN = -1073741824` (-2^30) as a constant causes selftest-c to fail during assembly with an invalid immediate expression. The compiled compiler (driver2) generates a huge negative literal `-1329227993309035794333046510482096127` (0xfffffff7ffffffffffffffffffffff) instead of the correct value.

**Root Cause**: Unknown. The value -1073741824 is exactly at the fixnum boundary (min_fixnum). When MRI Ruby parses it, it stays as a fixnum. But when the self-compiled compiler tries to compile it again during selftest-c, something in the literal parsing/generation logic produces an incorrect huge negative number.

**Workaround**: Integer::MIN is commented out in both `lib/core/integer_base.rb` and `lib/core/integer.rb`. The constant is not currently used anywhere in the codebase, so this has no functional impact.

**Location**:
- `lib/core/integer_base.rb:9`
- `lib/core/integer.rb:28`

**To Fix**: Debug why the literal -1073741824 gets corrupted during self-compilation. Likely issue in tokens.rb (Tokens::Int.expect) or in how the compiler emits integer constants at the fixnum boundary.

**Top Compilation Errors by Frequency** (excluding debug output):
1. ~~**Expected EOF** - 6 specs (alias, break, for, next, send, until)~~ ✅ **FIXED** (Session 41, commit 64e6e6b)
2. **Method call requires two values** (:should) - 5 specs - 📋 **DOCUMENTED** (Session 42) - See [control_structures_as_expressions.md](control_structures_as_expressions.md) - Requires architectural changes to support control structures (if/while/unless/begin) as expressions. Blocked pending design decision.
3. **Expected: do .. end block / Expected: '}'** - 5+ specs - 🔨 **PARTIAL FIX** (Session 42, commit c5b3d1a) - Stabby lambda inline parameters now supported: `->(x) {}`, `-> x {}`. **NOTE**: Some errors (magic_comment_spec, predefined_spec) are caused by run_rubyspec sed mangling, not parser bugs. Real remaining issues: splat parameters (`-> *x`), `.()` call syntax.
4. **Expected: ')'** - 4 specs - 🔨 **PARTIAL FIX** (Session 42, commit d185f83) - Keyword argument parsing implemented: `kw:`, `kw: default`, `**kwargs`. keyword_arguments_spec now parses. Remaining: assignments_spec (splat + begin), delegation_spec (hash in calls), super_spec (module issue).
5. **Expected: 'end' for 'do'-block** - 4 specs (class, execution, encoding, safe)

---

## TOP PRIORITY TASKS (Session 41+)

**Language Specs** (HIGHEST PRIORITY - unblock ~5-10 specs):
1. [x] Fix Scanner#position= bug (parser.rb:405, scanner.rb) - add setter method ✅ DONE (commit f541211)
2. [x] Improve error reporting with multi-line source context ✅ DONE (commits 1263f71, ce1a2b8, e055b6b)
   - [x] Centralized error formatting in CompilerError class
   - [x] Added ANSI color highlighting (cyan line numbers, red error lines, bright red markers)
   - [x] Implemented String#chomp and String#chomp! methods
   - [x] Added block_start_line support for showing block context
   - [x] Fixed double linefeed issue
   - [x] All error types (ParseError, ShuntingYardError) inherit formatting automatically
3. [x] Add begin/rescue else clause support (parser.rb parse_begin) ✅ DONE (commit c2c20da)
4. [x] Add begin/ensure block support (parser.rb parse_begin, tokens.rb, compiler.rb) ✅ DONE (commit 8bf7f18)
5. [x] Fix bare splat operator: `def foo(*); end` (parser.rb parse_arglist) ✅ DONE
6. [x] Fix "Expected EOF" for eigenclass/class/module as expression ✅ DONE (commit 64e6e6b)
7. [x] Fix keyword splat: `def foo(**kwargs); end` (parser.rb parse_arglist) ✅ DONE (commit d185f83)
8. [x] Add missing exception classes (lib/core/exception.rb) ✅ DONE (commit df6c7e2) - Added NameError, SyntaxError, LocalJumpError, NoMatchingPatternError, UncaughtThrowError
9. [x] Add ensure clause support to do..end blocks (parser.rb parse_block) ✅ DONE (commit 685e2f6) - Fixes 3 of 4 "Expected: 'end' for 'do'-block" errors
10. [x] Fix empty parentheses in expressions (shunting.rb) ✅ DONE (commit ab083aa) - Empty `()` now pushes `:nil` symbol instead of nil placeholder, fixing malformed AST nodes for `() && true`, `true && ()`, `() && ()`. Only applies to `()`, not `[]` or `{}`.
11. [x] Add split precedence support for assignment operators (operators.rb, shunting.rb) ✅ DONE (Session 42) - Assignment operators now have left precedence 7, right precedence 5, fixing `true && x = 1` parsing
12. [x] Add 'not' keyword operator (operators.rb) ✅ DONE (commit cc2c08b) - Maps to `!` with lower precedence (2 vs 8), improves not_spec from 4/16 to 9/10 tests
13. [x] Fix destructuring assignment to call to_a (transform.rb) ✅ DONE (commit b396759) - Destructuring like `x, y = nil` now converts RHS via to_a before indexing, fixing "undefined method '[]' for NilClass". and_spec now 10/10 tests.
14. [ ] Investigate brace syntax limitations (likely has bugs, not fully unsupported)
15. [ ] Fix shunting yard expression parsing errors (investigate case by case)

**Integer Specs** (Continue improvements):
12. [ ] Investigate and fix remaining 3 crashes (fdiv_spec, round_spec, times_spec)
13. [ ] Consider minimal Float implementation (would unblock ~10-15 specs)
14. [ ] Consider power/multiplication accuracy fix for large numbers (BUG 2)

**Note**: Exception handling now supported in self-hosted compiler - can use exceptions for error handling where appropriate

---

## Session 41 Status Summary

**Key Wins**:
- Integer#>> implementation complete (BUG 1 fixed) - +14 tests in right_shift_spec
- element_reference_spec CRASH→PASS (regression fix)
- Integer.sqrt optimization (>> 1 instead of / 2) - +18 tests
- Language spec compilation error analysis complete - identified critical parser bug

**Goal**: Fix compilation errors first (make specs compile), then improve pass rates

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
- Remaining failures: edge cases with very large shifts (> 2^24)

**Regression Fix** (commit a9b554e):
- element_reference_spec was CRASHING after Integer#>> implementation
- Root cause: `bignum[-0xffffffff]` → `bignum << 0xffffffff` tried to allocate 143M limbs
- Fix: Limit negative shifts to 2^24 bits (reasonable maximum)
- Result: element_reference_spec CRASH → PASS (P:20 F:16)

**Actual Effort**: ~1.5 hours (vs 4-6 hours estimated)
**Files**: `lib/core/integer.rb` (Integer#>>, __right_shift_fixnum, __right_shift_heap, __shift_limb_right_with_borrow)
**Commits**: eb53140 (implementation), a9b554e (regression fix)

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

## SESSION 41 ADDITIONAL WINS

### ✅ Integer#integer? method
- **Status**: COMPLETE (commit 9004b84)
- **Impact**: integer_spec P:1 F:3 → P:2 F:1 (+1 test)
- **Implementation**: Added predicate method that returns true for all integers
- **Files**: `lib/core/integer.rb:3476-3478`

### ⏸️ Integer include Comparable
- **Status**: PARTIAL - `include` statement added but doesn't work yet
- **Issue**: Requires runtime module tracking (Class#include? method)
- **Complexity**: Module inclusion tracking is complex to implement
- **Impact**: integer_spec still has 1 failure (Comparable check)
- **Decision**: Deferred - needs Module/Class implementation work
- **Files**: `lib/core/integer.rb:13`

---

## LANGUAGE SPECS - NEW TERRITORY

**Status**: Compilation error analysis complete (Session 41)
**Documentation**:
- [LANGUAGE_SPEC_ANALYSIS.md](LANGUAGE_SPEC_ANALYSIS.md) - Overall categorization
- [LANGUAGE_SPEC_COMPILATION_ERRORS.md](LANGUAGE_SPEC_COMPILATION_ERRORS.md) - **Detailed error analysis**

### Summary
- **79 total specs** testing Ruby language features
- **72 specs (91%) COMPILE FAIL** - mostly parser limitations
- **5 specs runtime failures**, **2 specs crash**
- **0 specs pass** (8% pass rate on individual tests)

### Compilation Error Categories (from 17 spec sample)
1. **Parser Bug** (CRITICAL): Scanner#position= missing - affects break_spec, string_spec
2. **Argument Parsing**: Splat/keyword arguments not supported - affects 3+ specs
3. **Begin/Rescue/Ensure**: Missing else/ensure support - affects 3+ specs
4. **Shunting Yard Errors**: Expression parsing issues - affects 4+ specs (needs better error reporting!)
5. **Multiple Assignment**: Destructuring not supported - affects 2+ specs
6. **Lambda Brace Syntax**: Likely has bugs/limitations (not fully unsupported) - affects lambda_spec
7. **Heredoc Parsing**: Various heredoc issues - affects heredoc_spec
8. **String/Symbol Parsing**: Edge cases - affects hash_spec
9. **Link Failures**: Missing exception classes (NameError) - affects loop_spec

**Note on Error Reporting**:
- Shunting yard errors need both human-readable output AND optional technical debug mode
- Parser errors should show context, line/column, and helpful suggestions
- Exceptions can now be used for error handling (self-hosted compiler supports it)

**Warning**: This is uncharted territory. Proceed cautiously!

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
