# Compiler Work Status

**Last Updated**: 2025-10-18 (session 14 - SEGFAULT fixes in progress)
**Current Test Results**: 67 specs | PASS: 13 (19%) | FAIL: 42 (63%) | SEGFAULT: 12 (18%)
**Individual Tests**: 989 total | Passed: 143 (14%) | Failed: 743 (75%) | Skipped: 103 (10%)

**For historical details about fixes in sessions 1-12**, see git history for this file.

---

## Current Active Work

### ✅ Session 13: Eigenclass Implementation (2025-10-18) - **COMPLETE**

**Files Modified**: `compiler.rb:785`, `localvarscope.rb`, `compile_class.rb:6-46,83-138`

**Fixes**:
1. Fixed vtable offset allocation - removed `:skip` to find nested `:defm` nodes
2. Added `eigenclass_scope` marker to LocalVarScope
3. Fixed eigenclass method compilation with unique naming
4. Fixed eigenclass object assignment using manual assembly

**Status**: Eigenclasses with methods now compile and work correctly. Basic tests pass.

---

### 📋 Session 14: SEGFAULT Investigation (2025-10-18) - **IN PROGRESS**

**Status**: Investigated remaining 12 SEGFAULT specs with actual testing

#### Current SEGFAULT Specs (12 total, 18% of all specs)

**1. times_spec - PARSER BUG**
- Parser bug with `or break` syntax - treats `break` as method name
- Fix Required: Update parser to handle `or break` / `or next` / `or return`
- File: `parser.rb` or `shunting.rb`

**2. plus_spec - SEGFAULT IN LAMBDA**
- ✅ Stub `ruby_exe` added to rubyspec_helper.rb (done)
- ❌ Still crashes - NOT due to ruby_exe
- Crash location: Address 0x5665e900 called from __method_Proc_call
- Backtrace: Crash occurs inside a lambda (rubyspec_temp_plus_spec.rb:85)
- Root Cause: NOT YET DETERMINED
  - Could be bug in code inside the lambda
  - Could be Proc/lambda infrastructure bug
  - Could be unrelated memory corruption
  - Need systematic debugging to isolate
- Fix Required: Create minimal test case and debug
- Effort: 3-6 hours

**3. divide_spec, div_spec - BUG IN DIVISION CODE**
- Crashes with SEGV at 0x00000011 in `__method_Integer___div`
- Root Cause: Bug in division code in lib/core/integer.rb
- Test contains `class << obj; private def coerce(n); [n, 3]; end; end`
- Fix Required: Debug and fix `div` method implementation
- Effort: 2-4 hours

**4. round_spec - PROC STORAGE BUG**
- Shared example mechanism has memory corruption in Proc handling
- Fix Required: Fix Proc storage/retrieval in rubyspec_helper.rb
- Effort: 3-6 hours

**5. ArgumentError Testing (comparison, exponent, fdiv, pow)**
- FPE crashes when specs test error handling (wrong arg counts)
- **IMPORTANT**: FPE is INTENTIONAL error signaling (used instead of exceptions)
- Fix Required: Change affected methods to use `*args` pattern, validate arg count, print error to STDERR, return safe value
- **This is a workaround** until exceptions are implemented
- Example pattern:
  ```ruby
  def method_name(*args)
    if args.length != expected_count
      STDERR.puts("ArgumentError: wrong number of arguments")
      return nil  # or appropriate safe value
    end
    actual_arg1, actual_arg2 = args
    # ... normal implementation
  end
  ```
- Effort: 1-2 hours per method, fixes 4 specs

**6. Other (try_convert, element_reference, to_r)**
- Need individual investigation

#### Priority Order

**Priority 1: Fix division bug (divide_spec, div_spec)**
- Debug and fix `div` method in lib/core/integer.rb
- Crash occurs in `__method_Integer___div`
- Effort: 2-4 hours
- Fixes: 2 specs

**Priority 3: Fix ArgumentError testing (comparison, exponent, fdiv, pow)**
- Change affected methods to use `*args` pattern with validation
- Workaround until exceptions are implemented
- Effort: 1-2 hours per method (4-8 hours total)
- Fixes: 4 specs

**Priority 4: Fix parser bug (times_spec)**
- Update parser for `or break` / `or next` / `or return` syntax
- File: `parser.rb` or `shunting.rb`
- Effort: 2-4 hours
- Fixes: 1 spec

**Priority 5: Fix Proc storage (round_spec)**
- Debug Proc block storage/retrieval in rubyspec_helper.rb
- Effort: 3-6 hours
- Fixes: 1 spec

**Priority 6: Fix eigenclass vtable bug (plus_spec)**
- Handle eigenclass method vtable registration
- Complex architectural issue from Session 13
- Effort: 4-6 hours
- Fixes: 1 spec

**Priority 7 (LOW - After all segfaults): Implement full ruby_exe**
- Actually execute subprocess compilation/execution
- Effort: 2-3 hours
- Improves: Test coverage quality

---

## Completed Recent Work (Summary)

**Bignum/Heap Integer Support** (Sessions 1-12, 2025-10-17):
- ✅ Fixed `<=>`, comparison operators, subtraction
- ✅ Implemented multi-limb division/modulo with floor division semantics
- ✅ Optimized division algorithm (binary long division)
- ✅ Fixed heap negation bug
- ✅ Added type safety to all arithmetic operators
- ✅ Fixed 6 SEGFAULT specs via preprocessing and stub methods
- **Result**: 13 PASS, 143 tests passing (14%), SEGFAULTs reduced from 34 to 12

For detailed session-by-session breakdown, see git history (`git log --follow docs/WORK_STATUS.md`).

---

## Quick Reference

### Test Commands
```bash
make selftest-c                                    # Check for regressions
./run_rubyspec rubyspec/core/integer/              # Full integer suite
./run_rubyspec rubyspec/core/integer/[spec].rb     # Single spec
```

### Key Files
- `lib/core/integer.rb` - Integer implementation
- `lib/core/fixnum.rb` - Fixnum-specific methods
- `docs/WORK_STATUS.md` - **THIS FILE** (update with every change)
- `docs/RUBYSPEC_STATUS.md` - Overall test status
- `docs/TODO.md` - Long-term plans

### Helper Methods Available
- `__cmp_*` (lines 906-1107) - Multi-limb comparison
- `__negate` (line 1363) - Negation for heap integers
- `__is_negative` (line 1341) - Sign check
- `__add_magnitudes`, `__subtract_magnitudes` - Arithmetic helpers

---

## Compiler Limitations

### Core Class API Immutability
**CRITICAL CONSTRAINT**: Cannot add/change public methods that don't exist in MRI Ruby

- ❌ **PROHIBITED**: Adding public methods to Object, NilClass, Integer, String, etc. that MRI doesn't have
- ✅ **ALLOWED**: Private helper methods prefixed with `__`
- ✅ **ALLOWED**: Stub out existing MRI methods (as long as method exists in MRI)
- **Rationale**: Must maintain Ruby semantics compatibility

### Exception Handling
**NOT IMPLEMENTED**: Cannot use `raise`, `begin/rescue/ensure`, or exception classes

**Workaround**: Return `nil` or safe values on errors, print to STDERR

```ruby
# CORRECT pattern (no exceptions available):
def some_method(arg)
  if arg.nil?
    STDERR.puts("Error: argument cannot be nil")
    return nil  # or some safe default value
  end
  # ... normal processing
end

# INCORRECT pattern (exceptions not supported):
def some_method(arg)
  raise ArgumentError, "argument cannot be nil" if arg.nil?  # WON'T WORK
end
```

---

## How to Update This Document

**After completing any task**:
1. Add new session section under "Current Active Work"
2. Update test status numbers at top
3. Run `make selftest-c` before and after changes
4. Commit with reference to this document

**When marking work complete**:
1. Move session from "Current Active Work" to "Completed Recent Work"
2. Keep only 2-3 most recent completed sessions
3. Remove older sessions (they remain in git history)

**This is the single source of truth for ongoing work. Always run `make selftest-c` before committing (must pass with 0 failures).**
