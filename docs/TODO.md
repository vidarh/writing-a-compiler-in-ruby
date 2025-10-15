# Ruby Compiler TODO

This document tracks known bugs, missing features, and architectural issues. Items are prioritized: critical bugs first, missing language features second, architectural improvements third.

**For debugging help, see [DEBUGGING_GUIDE.md](DEBUGGING_GUIDE.md) for effective patterns and techniques.**

## Current Integer Spec Test Status (2025-10-15) - COMPILE FAILURES ELIMINATED! ✅

**Summary**: 67 spec files total
- **PASS**: 11 files (16%)
- **FAIL**: 22 files (33%)
- **SEGFAULT**: 34 files (51%)
- **COMPILE_FAIL**: 0 files (0%) ✅ **ALL FIXED** - was 7 files, now 0!

**Individual Test Case Counts** (from enhanced run_rubyspec):
- **Total**: 747 individual test cases across all 67 spec files
- **Passing**: 142 test cases (19%)
- **Failing**: 605 test cases (81%)
- **Skipped**: 0 test cases

**Detailed Analysis**:
- `docs/INVESTIGATION_SUMMARY_2025-10-14.md` - Executive summary and next steps
- `docs/rubyspec_failure_analysis_2025-10-14.md` - Comprehensive root cause analysis
- `docs/QUICK_WINS_PLAN.md` - Detailed implementation plan with effort estimates

## PRIORITY QUICK WINS - Maximum Impact Per Effort (2025-10-14)

### 🎯 Phase 1: Bignum Foundation (HIGHEST IMPACT - +100-120 test cases)

**Issue**: The single largest cause of failures. Bignum tests use fake values and return completely wrong results.

**CRITICAL PREREQUISITE**: Large Integer Literal Support (4-8 hours)
- **Problem**: Tokenizer truncates integer literals > 2^27 (tokens.rb:193)
- **Impact**: Cannot write bignum_value() with actual large values
- **Fix Required (MUST be done in this order)**:
  1. **FIRST**: Add hard validation to sexp.rb - REJECT literals > 2^29 with fatal error
     - 🚨 **S-expressions CANNOT accept heap integers** - architectural constraint
     - S-expressions compile to assembly with immediate values (tagged fixnums)
     - Heap integers are pointers, not immediate values
     - Allowing heap integers in s-expressions = memory corruption
  2. **SECOND**: Remove truncation from tokens.rb - parse full integer literals
  3. **THIRD**: When literal > 2^29, return heap integer allocation AST node
  4. **FOURTH**: Compile heap integer allocation nodes
- **Files**: sexp.rb (FIRST), tokens.rb, parser.rb, compiler.rb
- **Risk**: HIGH - if s-expression validation not in place, will generate broken assembly
- **Test Strategy (strict order)**:
  1. **Phase A**: Add s-expression validation, test it rejects large values, run selftest-c
  2. **Phase B**: Audit all s-expressions for large literals (grep -r "%s" lib/)
  3. **Phase C**: Remove truncation, verify s-expressions still protected
  4. **Phase D**: Add parser support for [:bignum_alloc, ...] nodes
  5. **Phase E**: Add compiler support, test `x = 9223372036854775808`
  6. Run make selftest-c after EVERY phase

**Quick Wins**:
1. **Fix bignum_value() helper** (1-2 hours) - REQUIRES PREREQUISITE ABOVE
   - Location: `rubyspec_helper.rb:534`
   - Current: Returns `100000 + plus` (fake value)
   - Fix: Return actual heap integer object with value `0x8000_0000_0000_0000 + plus`
   - Impact: Enables all bignum tests to use real values
   - Affected specs: abs, even, odd, to_s, plus, multiply, left_shift, bit_and, and 30+ more

2. **Fix multi-limb to_s edge cases** (2-4 hours)
   - Location: `lib/core/integer.rb` (to_s method for heap integers)
   - Status: Mostly working according to docs/bignums.md, but has bugs with large values
   - Impact: Fix to_s_spec.rb (+7 test cases), improve debug output for all bignum tests

3. **Fix heap integer operators** (PARTIAL - 2025-10-14)
   - Location: `lib/core/integer.rb`
   - **Status**: ✅ FIXED: `>`, `>=`, `<`, `<=` now work with multi-limb heap integers
   - **Status**: ✅ WORKING: `+`, `-`, `*` (binary operators work via existing heap integer implementations)
   - **Status**: ❌ BROKEN: Many operators still use `__get_raw`, only work for single-limb:
     - **Comparison**: `<=>` (spaceship), `==` (equality)
     - **Arithmetic**: `/`, `-@`, `%`, `mul`, `div`, `pred`
     - **Bitwise**: `&`, `|`, `^`, `<<`, `>>`
     - **Other**: `abs`, `zero?`, `inspect`, `chr`
   - **Remaining work** (10-15 hours total):
     - Comparison: Update `<=>` to dispatch to `__cmp_*` methods (1 hour)
       - **Refactor**: Then reimplement `>`, `>=`, `<`, `<=`, `==` in terms of `<=>`
       - Current: Each has duplicate dispatch logic (~30 lines each)
       - Improved: `def > other; (self <=> other) == 1; end` (~1 line each)
       - Saves ~135 lines, improves maintainability
     - Arithmetic: Implement multi-limb division, modulo, etc. (4-6 hours)
     - Bitwise: Implement limb-by-limb bitwise operations (3-4 hours)
     - Other: Update to handle multi-limb (1-2 hours)
   - Impact: Fix comparison_spec.rb, bit_*_spec.rb, arithmetic specs, +50-80 test cases

**Expected Total Gain**: +100-120 passing test cases across 25+ spec files

### 🎯 Phase 2: Type Coercion (HIGH IMPACT - +50-60 test cases)

**Issue**: Operators call `__get_raw` without type checking, causing "Method missing X#__get_raw" crashes.

**Quick Wins**:
1. **Add type checking to all operators** (2-3 hours)
   - Locations: `lib/core/integer.rb` (bitwise operators: &, |, ^, <<, >>)
   - Pattern (from DEBUGGING_GUIDE.md:230):
     ```ruby
     def & other
       if other.is_a?(Integer)
         other_raw = other.__get_raw
         %s(__int (bitand (callm self __get_raw) other_raw))
       else
         STDERR.puts("TypeError: Integer can't be coerced")
         nil
       end
     end
     ```
   - Impact: Fix plus_spec, multiply_spec, bit_and_spec segfaults (+30-40 test cases)

2. **Implement to_int coercion protocol** (3-4 hours)
   - Pattern already in ceildiv (fixnum.rb:437-439)
   - Apply to all operators before calling __get_raw
   - Impact: Fix coercion test cases (+20-30 test cases)

**Expected Total Gain**: +50-60 passing test cases across 15+ spec files

### 🎯 Phase 3: Critical Method Gaps (MEDIUM IMPACT - +30-50 test cases)

**Quick Wins**:
1. **Fix/implement divmod** (2-3 hours)
   - Currently: Immediate FPE crash
   - Impact: Fix divmod_spec.rb (+10-20 test cases)

2. **Audit heap integer methods for nil returns** (2-4 hours)
   - Issue: "Method missing NilClass#__multiply_heap_by_fixnum"
   - Find methods returning nil instead of Integer objects
   - Impact: Fix multiply_spec.rb and similar (+10-20 test cases)

3. **Fix negative shift handling** (2-3 hours)
   - Issue: left_shift_spec shows "Expected -1 but got 0" for negative shifts
   - Location: Integer#<< and Integer#>> methods
   - Impact: Fix left_shift_spec edge cases (+10-15 test cases)

**Expected Total Gain**: +30-50 passing test cases across 10+ spec files

### 📊 Estimated Overall Impact

**After Phase 1-3 (Total effort: ~25-35 hours)**:
- Current: ~100-150 passing test cases (20-25%)
- After fixes: ~280-380 passing test cases (50-65%)
- **Improvement**: +180-230 passing test cases (+30-40 percentage points)

**Files likely to reach 100% passing**:
- abs_spec.rb (1/3 → 3/3)
- even_spec.rb (4/6 → 6/6)
- odd_spec.rb (similar to even)
- to_s_spec.rb (8/15 → 15/15)
- bit_and_spec.rb (7/18 → 18/18)
- magnitude_spec.rb (likely same issues as abs)
- And 10-15 more specs

### 🔧 Implementation Strategy

**Step 1: Fix bignum_value() FIRST**
- This is the foundation - without real bignum values, can't test anything
- Changes rubyspec_helper.rb only
- Run make selftest-c to ensure no regressions

**Step 2: Test one spec at a time**
- Start with abs_spec.rb (simplest)
- Fix issues iteratively
- Verify with: `./run_rubyspec rubyspec/core/integer/abs_spec.rb`

**Step 3: Move to progressively complex specs**
- abs → even → to_s → bit_and → plus → multiply
- Each fix builds on previous fixes

**Session 2025-10-10 Additions**:
- ✅ Added `Mock#with(*args)` stub method
- ✅ Added `infinity_value` helper method
- ✅ Disabled MockInt class (causes crash during class definition)
- ✅ Confirmed blocks with parameters work perfectly in methods
- ✅ Confirmed lambdas (including `->` syntax) work in methods
- ✅ Documented that `(div 1 0)` in `__printerr` is intentional crash mechanism
- ✅ **FIXED**: Global variable initialization order - moved `$before_each_blocks` and `$after_each_blocks` to top of rubyspec_helper.rb
- ✅ **FIXED**: Unary plus operator (`+5`) - was not implemented at all
  - Added transformation in transform.rb:178-182 to convert `[:+, operand]` to `[:callm, operand, :+@, []]`
  - Added `Integer#+@` method in lib/core/integer.rb:21-23 (returns self)
  - Fixed double-wrapping bug: was doing `E[e[1]]` instead of `e[1]`
- ✅ **abs_spec now passes!** (1 test passing, 2 bignum failures)
- ✅ **FIXED**: ceildiv type coercion - now calls `to_int` on non-Integer arguments before using `%` or `/`
  - Fixed lib/core/fixnum.rb:437-439 to use `is_a?(Integer)` check instead of broken `respond_to?`
  - This allows Rational and other numeric types to be properly converted
  - ceildiv itself works correctly now
- ⚠️ **DISCOVERED**: Parser bug with negative numbers (see docs/parser_negative_number_bug.md)
  - `-4.method` parsed as binary subtraction after expressions with negative args
  - Blocks ceildiv_spec from passing (crashes due to misparsing)
  - **Root cause**: Tokenizer `@lastop` flag not reset after newlines when expression is complete
  - **Fix location**: Requires expression-aware context in `shunting.rb` or `parser.rb`, not tokenizer
  - **Workaround**: Use `(-4).method` with parentheses
- **Remaining issues**: Still investigating other segfaults

**Latest Additions**:
- ✅ Rational literal syntax support (`5r`, `6/5r`) - COMPLETE
- ✅ Block parameters work correctly inside methods
- ✅ Nested blocks (describe/context/it) work correctly
- ⚠️ Remaining segfaults are edge cases with very complex nested structures

**Major Achievement**: All rubyspec/core/integer tests now compile successfully! This represents significant progress in parser/compiler completeness.

**Current Focus**: Fixing bitwise operator coercion (see docs/BITWISE_OPERATOR_COERCION.md).

**Root Causes Identified** (see docs/segfault_analysis_2025-10-09.md and docs/segfault_investigation_journal.md for details):

1. **Block Parameter Bug** (PRIMARY - affects ~19-28 specs)
   - Block parameters like `|value|` treated as method calls
   - Confirmed with test: "Method missing Object#x" for `[1,2,3].each do |x|`
   - Affects: abs, magnitude, times, downto, upto, and all specs using shared examples with blocks

2. **Symbol Parsing Issue** (affects 1 spec)
   - Symbol `:-@` parsed incorrectly as `:-` + `@`
   - uminus_spec fails with "Method missing Object#@"
   - Direct unary minus works fine

3. **Stub Method Issues** (affects 3-5 specs)
   - bit_length: Always returns 32 (but NOT causing segfault)
   - ceildiv: Logic bugs, also hits Rational literal `6/5r`
   - size: Works, segfault from other causes (bignum tests)
   - to_f: ✅ Added stub (returns integer not Float)

**Other Issues**:
1. Lambda specs need investigation - compiler HAS lambda support, need to identify specific failing syntax
2. Bignum emulation using regular fixnums produces incorrect values

## Recent Additions

### 2025-10-15 - Tokenizer Float Literal Fix

**✅ FIXED: All COMPILE FAIL specs now compile**

Fixed critical tokenizer bug where large float literals (e.g., `4294967295.0`) caused compilation failures.

**Root Cause**:
- Tokenizer checked if integer exceeded fixnum range BEFORE checking for decimal point
- When seeing `4294967295.0`, it converted `4294967295` to heap integer AST, then failed when trying to append `.0`

**Solution**:
- Reordered checks in tokens.rb Number.expect()
- Now checks for float/rational literals FIRST, then converts large integers to heap integers

**Impact**:
- ✅ divide_spec.rb: COMPILE FAIL → SEGFAULT (now compiles!)
- ✅ div_spec.rb: COMPILE FAIL → SEGFAULT (now compiles!)
- ✅ minus_spec.rb: COMPILE FAIL → SEGFAULT (now compiles!)
- ✅ plus_spec.rb: COMPILE FAIL → SEGFAULT (now compiles!)
- ✅ exponent_spec.rb: COMPILE FAIL → SEGFAULT (now compiles!)
- ✅ pow_spec.rb: COMPILE FAIL → SEGFAULT (now compiles!)
- ✅ to_f_spec.rb: COMPILE FAIL → SEGFAULT (now compiles!)
- ✅ make selftest-c: 0 failures

**Files Modified**: tokens.rb

---

## Recent Additions

### 2025-10-09 - Segfault Investigation & Fixes

**Investigation Completed**: Systematically analyzed all 43 segfaulting integer specs
- See `docs/segfault_analysis_2025-10-09.md` for detailed categorization

**Fixes Applied**:
1. ✅ **Symbol Parsing for Unary Operators** (sym.rb:33-46)
   - Added support for `:-@` and `:+@` symbols
   - Fixed: uminus_spec.rb (SEGFAULT → FAIL)

2. ✅ **Bitwise Operator Assembly Instructions** (emitter.rb:458-460)
   - Implemented `andl`, `orl`, `xorl` emitter methods
   - Required for bitwise operations to generate valid assembly

3. ✅ **Bitwise Operator Result Tagging** (fixnum.rb:170-182)
   - Wrapped `&`, `|`, `^` results in `__int()` to restore type tag
   - Critical fix: bitwise operations were returning untagged integers
   - Fixed: allbits_spec.rb, anybits_spec.rb, nobits_spec.rb (SEGFAULT → FAIL)

4. ✅ **Added Fixnum#to_f stub** (fixnum.rb:302-306)
   - Partial fix for to_f_spec.rb (still needs proper Float conversion)

**Known Issue Discovered**:
- **Bitwise Operator Type Coercion Bug** (see `docs/bitwise_operator_coercion_bug.md`)
  - Operators call `__get_raw` without type checking or calling `to_int` first
  - Workaround: Added `Mock#__get_raw` stub (rubyspec_helper.rb:100-112)
  - Proper fix needed: Implement coercion protocol in operators

5. ✅ **Shift Operators (`<<`, `>>`)** (compile_arithmetic.rb:29-67, fixnum.rb:190-204)
   - Implemented `compile_sall` and `compile_sarl` (were marked FIXME: Dummy)
   - Fixed s-expression argument order: (sall shift_amount value_to_shift)
   - Shift operators now work correctly for basic cases
   - Note: left_shift_spec and right_shift_spec still segfault on Mock#stub!, but operators work

**Results**:
- Segfaults: 43 → 39 (4 specs fixed)
- Failures: 16 → 20 (specs now run but have assertion failures)
- Selftest: ✅ Still passing
- Shift operators: ✅ Working (verified with manual tests)

### 2025-10-09
- **Added `Fixnum#abs` and `Fixnum#magnitude`** - Returns absolute value of an integer
  - Works correctly when called directly or via `.send(:abs)`
  - Blocked from full testing by block parameter issue

### 2025-10-07

### ✅ Completed Features

**Exclusive Range Operator (...)** - WORKING
- Added `...` operator to `operators.rb`
- Updated `Range` class with `exclude_end` parameter
- Added transform rewrite for `:exclusive_range`
- Result: `ceil_spec` and `floor_spec` now compile

**Hex/Binary Literal Parsing** - WORKING
- Enhanced `tokens.rb` to support `0x` (hex) and `0b` (binary) prefixes
- Supports underscores as separators: `0xFFFF_FFFF`, `0b1010_1010`
- Respects 29-bit limit to prevent overflow
- Result: No more "Method missing Object#xffff" errors

**Float Literal Support** - WORKING (but blocked by context issue)
- Created `Float` class with instance variables reserving 8-byte space
- Added float constant collection/emission in `compiler.rb`
- Added FPU instructions (`fldl`, `fstpl`) to `emitter.rb`
- Float arithmetic operations are stubs (return self, 0, false)
- Result: Float literals compile without crashes, but most specs using floats also use `context`

**Operator/Method Stubs Added** (`lib/core/fixnum.rb`):
- Bitwise: `&`, `|`, `^`, `~`, `<<`, `>>` (stub implementations)
- Math: `**`, `-@`, `truncate`, `gcd`, `lcm`, `gcdlcm`, `ceildiv`
- Predicates: `even?`, `odd?` (mostly working)
- Result: 8+ specs moved from SEGFAULT to FAIL

**Rational Support** - WORKING
- Added `Rational` class (`lib/core/rational.rb`) - ✅ Fixed typo (was "initizalize")
- Added `Integer#numerator`, `Integer#denominator`, `Integer#to_r`
- Required in `lib/core/core.rb`

**Rational Literal Syntax** (2025-10-09) - ✅ COMPLETE
- **Tokenizer changes** (`tokens.rb`):
  - `Number.expect` now recognizes `<number>r` → `[:call, :Rational, [number, 1]]`
  - Recognizes `<number>/<number>r` → `[:call, :Rational, [numerator, denominator]]`
  - Proper backtracking: if `/` not followed by `<number>r`, ungets and continues normally
  - Examples: `5r` → `Rational(5, 1)`, `6/5r` → `Rational(6, 5)`
- **Rational class enhancements** (`lib/core/rational.rb`):
  - Added `to_i` (truncate to integer)
  - Added `to_int` (type coercion - same as to_i)
  - Added `to_f` (convert to float)
  - Added `coerce` method for arithmetic operations
- **Type coercion in ceildiv** (`lib/core/fixnum.rb`):
  - `ceildiv` now calls `to_int` on non-integer arguments
  - This is the PROPER place for type coercion (not in `__get_raw`)
  - Result: `3.ceildiv(6/5r)` → `3.ceildiv(1)` → `3` ✅
- **Testing**:
  - Manual tests pass: rational literals work correctly
  - ceildiv with Rational works correctly
  - Selftest passes (no regressions)
  - ceildiv_spec still segfaults (likely due to lambda/block parameter bug, not Rational)

**Spec Helper Improvements** - COMPLETE FOR THIS SESSION
- ✅ Added `be_kind_of` matcher (moved 3 specs from SEGFAULT to FAIL)
- ✅ Added `Mock#and_raise` method
- ✅ Fixed `require_relative` for fixtures (moved 5 specs from COMPILE_FAIL)
- ✅ Added Encoding stub class with constants (US_ASCII, UTF_8, etc.)
- ✅ Added Math::DomainError exception class
- ✅ Added String#encoding method (to_s_spec now runs, passes encoding tests)
- ✅ Added Fixnum#digits stub method (digits_spec now runs)
- Already has: `context`, `platform_is`, `ruby_version_is`, matchers, shared examples

### 🐛 Known Bugs

#### Parser Bugs
- **Negative Number Parsing Bug** (HIGH PRIORITY - see docs/parser_negative_number_bug.md)
  - Parser treats `-4.method` as binary subtraction in certain contexts
  - Occurs when negative-arg expression is followed by negative-receiver expression
  - Example: `4.ceildiv(-3)` followed by `-4.ceildiv(3)` parses as subtraction
  - Workaround: Use `(-4).ceildiv(3)` with parentheses
  - Affects: ceildiv_spec and potentially other specs with consecutive negative numbers
- `tokens.rb:383` - nil error triggered by `context` keyword usage
- `tokens.rb:320` - affects some specs (gcd_spec, lcm_spec, pow_spec)

## Critical Missing Language Features

### Exception Handling
- **Priority: High**
- Limited begin/rescue support
- No ensure blocks
- Basic infrastructure exists but commented out for bootstrap
- **File**: `driver.rb:45-50`

### Regular Expressions
- **Priority: High**
- No regex support at all
- Many Ruby libraries depend on regex
- **Workaround**: String manipulation methods only

### Dynamic Code Execution
- **Priority: Medium**
- No eval, no runtime code generation
- **Rationale**: Conflicts with ahead-of-time compilation model

### Lambda Syntax (->)
- **Priority: High**
- Stabby lambda `-> { }` not supported
- Blocks ~30+ modern Ruby specs
- Parser treats `->` as minus + greater-than
- **Note**: Lambda usage in specs is mostly for exception testing - may be workable via rubyspec_helper workarounds

### HEREDOC Syntax (HIGH PRIORITY)
**Status**: NOT IMPLEMENTED - breaks multiple specs (plus_spec, to_f_spec, etc.)

Two-phase implementation plan:

#### Phase 1: Inline HEREDOCs (SIMPLER - DO FIRST)
**Syntax**: `foo(<<HEREDOC\n...\nHEREDOC)`
- Content is inline with the statement
- Can potentially be treated as a token during scanning
- Less complex to implement
- **Approach**: Extend tokenizer to recognize and capture HEREDOC as complete token

#### Phase 2: Deferred HEREDOCs (COMPLEX - DO LATER)
**Syntax**: `foo(<<HEREDOC)\n...\nHEREDOC`
- Content appears on following lines after the statement
- Requires parser to handle deferred token stream
- Less common in rubyspec tests
- **Approach**: Parser state machine to defer HEREDOC body consumption

**Files to modify**:
- `tokens.rb` - Add HEREDOC token recognition
- `scanner.rb` - Handle HEREDOC body scanning
- `parser.rb` - Process HEREDOC tokens

### Module System
- Include mechanism incomplete
- Constant resolution gaps
- Method precedence unclear (superclass vs eigenclass)

### Method Features
- Default arguments: Limited support
- Keyword arguments: Not implemented
- Method visibility (private/protected): Not supported
- alias/alias_method: Not implemented
- undef_method: Not implemented

## Segfault Issues (43 specs - PRIMARY FOCUS)

Most segfaults are due to:
1. Method not in vtable → `method_missing` → division by zero → SIGFPE
2. Specs using `.send(@method)` to call dynamically
3. Stub methods that are incomplete or incorrect
4. Missing method implementations in vtable at compile time

**Investigation approach**: Run individual specs with `./run_rubyspec rubyspec/core/integer/[spec_file]` and debug with `gdb` on the generated binary.

## Architectural Issues

### Performance
- Simple mark-and-sweep GC inefficient for many small objects
- Excessive object creation during compilation
- No object pooling for frequently allocated types

### Code Generation
- No inlining - method calls always involve full dispatch
- Poor constant folding
- No dead code elimination
- Some assembly patterns suboptimal

### Register Allocation
- Simple allocator, opportunities for improvement
- Cross-call preservation needs work
- Naive spilling strategy

### Error Handling
- Poor error messages in many places
- Inconsistent error location reporting
- Limited error recovery in parser

## Testing Infrastructure

### Spec Helper Needs (Most Complete)
- [x] Shared examples support - DONE
- [x] `context` implementation - DONE (alias for describe)
- [x] `be_kind_of` matcher - DONE
- [x] `platform_is` guard - DONE (stub)
- [x] `require_relative` support - DONE
- [ ] Mock improvements (and_raise implemented, may need more)
- [ ] `Object#Integer` method - not critical yet

### Test Coverage
- Self-test is minimal
- No comprehensive integration tests
- Bootstrap process requires manual verification

## Priority Assessment

### CRITICAL (blocks 43 integer specs - 64%)
1. **Fix block parameter handling** - Block parameters like `|value|` are treated as method calls
   - Affects any spec using `.each do |param|` or similar patterns
   - Root cause of most segfaults in integer specs
   - Files to investigate: `parser.rb`, `compiler.rb` (block compilation)
2. Complete stub method implementations (bitwise operators, arithmetic edge cases)
3. Fix bignum emulation (currently using small fixnum values)

### HIGH (for robustness)
1. Exception handling (begin/rescue/ensure)
2. Lambda syntax (`->`)
3. Better error reporting

### MEDIUM (for feature completeness)
1. Regular expressions
2. Full Float arithmetic (not just literals)
3. Complete object model features
4. Advanced optimizations

## Development Process

### Build System
- All builds require Docker (i386 environment)
- Some manual steps not automated
- Platform specific (x86 32-bit)

### Debugging
- Basic STABS support only
- Assembly debugging challenging
- Difficult to track down segfaults

### Documentation
- Architecture docs limited
- Many interfaces undocumented
- Inconsistent commenting

---

**Note**: For historical information about fixed bugs, see FIXED-ISSUES.md
