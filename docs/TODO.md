# Ruby Compiler TODO

**Purpose**: Task list for improving rubyspec integer test pass rate.
**Format**: One-line tasks. Details in referenced docs.
**Rule**: Only work on tasks that improve rubyspec test results.

**IMPORTANT**: Validate tasks before starting - check if already completed.

**Current Status**: 18/67 specs passing (27%), 265/507 tests passing (52%)
**Goal**: Maximize test pass rate by fixing root causes

**For details**: See [RUBYSPEC_STATUS.md](RUBYSPEC_STATUS.md)
**For ongoing work**: See [WORK_STATUS.md](WORK_STATUS.md) (journaling space)
**For debugging**: See [DEBUGGING_GUIDE.md](DEBUGGING_GUIDE.md)

---

## IMMEDIATE: Re-assess TODO List Based on Current Failures @fixed

**Completed** (Session 32, 2025-10-27): Verified all specs and updated status.

**Key Findings**:
- ✓ ceil_spec.rb: NOW PASS (was P:7 F:2, now P:9 F:0) - fixed by commits 94a989c, aeedc76
- ✓ truncate_spec.rb: NOW PASS (was P:4 F:1, now P:5 F:0) - fixed by commit aeedc76
- ✓ sqrt_spec.rb: Improved from CRASH to FAIL (P:4 F:3) - fixed by commit a6ea0ce
- ✓ bit_and_spec.rb: Improved from P:8 F:5 to P:10 F:3
- ✓ Updated spec_failures.txt with current results
- ✓ Current status: 18/67 specs (27%), 265/507 tests (52%)
- ✓ Updated task list with current crash/fail status for all sections

**Crash Status Updates**:
- Added: pow_spec and exponent_spec crash (not previously listed)
- Corrected: round_spec FAILS (not crashes as previously stated)
- Confirmed: divide_spec, divmod_spec, div_spec, times_spec still crash

**Files**: `spec_failures.txt` (updated), `docs/TODO.md` (task statuses updated)
**Result**: TODO list now reflects actual current state of all specs

---

## HIGH PRIORITY: Bitwise Operators for Negative Numbers (+7 tests) - COMPLETED ✓

**Final Status (2025-10-27 Session 32)**: Two's complement implemented and working correctly
- bit_and_spec: P:11 F:2 (was P:9 F:4) → **+2 tests**
- bit_or_spec: P:7 F:5 (was P:6 F:6) → **+1 test**
- bit_xor_spec: P:6 F:7 (was P:5 F:8) → **+1 test**
- allbits_spec: P:4 F:0 (was P:3 F:1) → **+1 test ✓ NOW PASS**
- anybits_spec: P:4 F:0 (was P:3 F:1) → **+1 test ✓ NOW PASS**
- nobits_spec: P:4 F:0 (was P:3 F:1) → **+1 test ✓ NOW PASS**
- **Total: +7 tests passing**

**Completed (Session 32)**:
- [x] Implemented special case: `X & -1 = X` (most common case)
- [x] Research two's complement representation for Ruby integers
- [x] Design algorithm to convert negative Integer to two's complement limb array
- [x] Implement conversion helper methods: `__magnitude_to_twos_complement`, `__invert_limb`, `__add_with_carry`, etc
- [x] Update `Integer#&` to handle all negative operands via two's complement
- [x] Update `Integer#|` to handle negative operands via two's complement
- [x] Update `Integer#^` to handle negative operands via two's complement
- [x] Verify allbits/anybits/nobits specs - all now PASS

**Remaining Failures (Not Related to Two's Complement)**:
- Float type checking: bit_and/bit_or/bit_xor should raise TypeError for Float (LOW PRIORITY)
- Integer#<< failures: Large shifts like `1 << 33` incorrectly produce small values (SEPARATE ISSUE - see LOW PRIORITY section below)

**Files**: `lib/core/integer.rb:2291-2298` (-1 special case), `2348-2550` (two's complement helpers and updated __bitand/bitor/bitxor_heap_heap)
**Time spent**: 5 hours
**Commits**: 8661b29 (special case), 58fe4d6 (full two's complement)

---

## HIGH PRIORITY: Heap Integer Division (+40-60 tests)

**Current Status (2025-10-27)**: divide_spec CRASHES, divmod_spec CRASHES, div_spec CRASHES, modulo_spec FAILS (P:8 F:8), remainder_spec FAILS (P:2 F:5)

**Impact**: 3 specs crash, 2 specs fail with heap integer division/modulo operations

- [ ] Research multi-limb division algorithms (Knuth Algorithm D or simpler)
- [ ] Implement multi-limb division helper (e.g., `__div_heap_heap`)
- [ ] Implement multi-limb modulo helper (e.g., `__mod_heap_heap`)
- [ ] Update `Integer#/` to dispatch to multi-limb division
- [ ] Update `Integer#%` to dispatch to multi-limb modulo
- [ ] Implement `Integer#divmod` using division and modulo
- [ ] Handle negative dividend cases
- [ ] Handle negative divisor cases
- [ ] Handle division by zero (should raise ZeroDivisionError once exceptions work)
- [ ] Test divmod_spec
- [ ] Test div_spec
- [ ] Test modulo_spec

**Files**: `lib/core/integer.rb`
**Estimated effort**: 8-12 hours

---

## HIGH PRIORITY: Integer Power/Exponent Operations - CRASHES

**Current Status (2025-10-27)**: pow_spec CRASHES, exponent_spec CRASHES

**Impact**: 2 specs crash when running power/exponent operations

- [ ] Investigate why Integer#** (power operator) causes crashes
- [ ] Check if issue is with heap integer exponentiation
- [ ] Implement or fix heap integer power algorithm
- [ ] Verify pow_spec no longer crashes
- [ ] Verify exponent_spec no longer crashes

**Files**: `lib/core/integer.rb`
**Estimated effort**: 4-8 hours
**Note**: WORK_STATUS.md Session 30 incorrectly claimed these were fixed

---

## MEDIUM PRIORITY: Parser Bugs (+3-13 tests)

**Current Status (2025-10-27)**: times_spec CRASHES, round_spec FAILS (P:4 F:13 S:1)

### Boolean Operators (`or`/`and`) Parser Bug - CAUSES CRASH

**Impact**: times_spec crashes during compilation

- [ ] Add `or` and `and` to operators list with correct precedence
- [ ] Update parser to recognize `or`/`and` as boolean operators (not method names)
- [ ] Test `a.shift or break` syntax parses correctly
- [ ] Verify times_spec no longer crashes

**Files**: `parser.rb`, `shunting.rb`, `operators.rb`
**Estimated effort**: 4-6 hours

### Keyword Argument Hash Literal Parser Bug - CAUSES FAILURES

**Impact**: round_spec fails 13/18 tests (P:4 F:13 S:1) - does NOT crash

- [ ] Research Ruby's implicit hash syntax in method calls
- [ ] Update parser to detect `:` not part of ternary operator
- [ ] Create implicit hash node when parsing `key: value` patterns
- [ ] Test `method(half: :up)` syntax parses correctly
- [ ] Verify round_spec passes all tests

**Files**: `parser.rb`, `shunting.rb`
**Estimated effort**: 6-10 hours

---

## MEDIUM PRIORITY: Type Coercion (+20-40 tests)

**Impact**: Specs using Mock objects and mixed-type operations

- [ ] Add coercion to `Integer#*`
- [ ] Add coercion to `Integer#/`
- [ ] Add coercion to `Integer#%`
- [ ] Add coercion to `Integer#<=>` (spaceship)
- [ ] Add coercion to `Integer#==`
- [ ] Add coercion to bitwise operators (`&`, `|`, `^`, `<<`, `>>`)
- [ ] Verify plus_spec passes coercion tests
- [ ] Verify multiply_spec passes coercion tests

**Files**: `lib/core/integer.rb`
**Pattern**: Check `respond_to?(:coerce)` before `respond_to?(:to_int)` (see Session 23)
**Estimated effort**: 3-5 hours

---

## LOW PRIORITY: Other Integer Methods

- [ ] **Fix Integer#<< for large shift amounts** (e.g., `1 << 33` produces 2 instead of 8589934592) - BLOCKS bit_or/bit_xor spec tests
- [ ] Fix negative shift handling in `Integer#<<`
- [ ] Fix negative shift handling in `Integer#>>`
- [ ] Implement multi-limb `Integer#<=>` (spaceship)
- [ ] Refactor comparison operators to use `<=>` (reduces duplication)
- [ ] Fix multi-limb `Integer#to_s` edge cases
- [ ] Audit heap integer methods for nil returns
- [ ] Add Float type checking to operators (should raise TypeError)

**Files**: `lib/core/integer.rb`, `lib/core/fixnum.rb`
**Note**: Integer#<< currently uses s-expression with `sall` which only handles fixnum shifts correctly

---

## LOWEST PRIORITY: Bugs Not Blocking Rubyspec

These should only be worked on if they directly block rubyspec test improvements.

### Self-Hosted Compiler Variable Initialization

**Status**: Workaround in place (`parser.rb:155`)
- [ ] Investigate compiler.rb local variable initialization code generation
- [ ] Fix root cause so all local variables initialize to nil
- [ ] Remove workaround from parser.rb

**Files**: `compiler.rb`, `parser.rb:155-156`
**Test**: `test_uninitialized_var.rb`

### Ternary Operator Bug

**Issue**: Returns boolean instead of selected branch in some cases
- [ ] Investigate ternary operator compilation in `compiler.rb`
- [ ] Fix to return selected branch value, not condition result

**Test**: `test_class_new_behavior.rb`

---

## Language Features (Only If Blocking Rubyspec)

### Exception Handling Enhancements

**Status**: Basic support implemented (Session 29). Missing features:
- [ ] Implement typed rescue (`rescue SpecificError`)
- [ ] Implement rescue variable binding (`rescue => e`)
- [ ] Implement multiple rescue clauses
- [ ] Implement ensure blocks
- [ ] Implement retry support

**Files**: `lib/core/exception.rb`, `compiler.rb`
**Ref**: WORK_STATUS.md Session 29

### HEREDOC Syntax

**Status**: Not implemented
- [ ] Phase 1: Implement inline HEREDOC (`foo(<<HEREDOC\n...\nHEREDOC)`)
- [ ] Phase 2: Implement deferred HEREDOC (`foo(<<HEREDOC)\n...\nHEREDOC`)

**Files**: `tokens.rb`, `scanner.rb`, `parser.rb`

### Other Language Features

- [ ] Regular expressions (no support currently)
- [ ] Full Float arithmetic (literals work, operations stubbed)
- [ ] Keyword arguments for methods
- [ ] Method visibility (private/protected)
- [ ] alias/alias_method
- [ ] undef_method
- [ ] eval/runtime code generation (conflicts with AOT model)

---

## Architecture & Infrastructure (Not Urgent)

### Compiler Improvements
- [ ] Implement method inlining
- [ ] Add constant folding optimization
- [ ] Add dead code elimination
- [ ] Improve register allocation
- [ ] Optimize assembly patterns

### Error Reporting
- [ ] Improve compiler error messages
- [ ] Add consistent error location reporting
- [ ] Enhance parser error recovery

### Testing
- [ ] Expand self-test coverage
- [ ] Add integration tests
- [ ] Automate bootstrap verification

### Documentation
- [ ] Expand architecture documentation
- [ ] Document interfaces
- [ ] Improve code comments

---

**Historical Info**: See FIXED-ISSUES.md for completed work
