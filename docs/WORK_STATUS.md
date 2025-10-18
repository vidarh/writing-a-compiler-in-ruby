# Compiler Work Status

**Last Updated**: 2025-10-18 (session 14 - SEGFAULT investigation)
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

**2. plus_spec - MISSING TEST FRAMEWORK METHOD**
- Missing `ruby_exe` method in rubyspec_helper.rb
- Fix Required: Add subprocess execution (compile/execute/capture output)
- Effort: 1-2 hours

**3. divide_spec, div_spec - RUNTIME CRASH**
- Crashes with SEGV at 0x00000011 in `__method_Integer___div`
- Root cause NOT YET DETERMINED - needs minimal test case
- Test contains `class << obj; private def coerce(n); [n, 3]; end; end`

**4. round_spec - PROC STORAGE BUG**
- Shared example mechanism has memory corruption in Proc handling
- Fix Required: Fix Proc storage/retrieval in rubyspec_helper.rb
- Effort: 3-6 hours

**5. ArgumentError Testing (comparison, exponent, fdiv, pow)**
- FPE crashes when specs test error handling (wrong arg counts)
- Fix Required: Add FPE signal handling to rubyspec_helper.rb
- Effort: 2-3 hours, fixes 4 specs

**6. Other (try_convert, element_reference, to_r)**
- Need individual investigation

#### Priority Order

**Priority 1: Investigate divide_spec/div_spec**
- Create minimal test case to determine if issue is eigenclass/division/coercion-related
- Effort: 1-2 hours investigation

**Priority 2: Fix parser bug (times_spec)**
- Update parser for `or break` syntax
- Effort: 2-4 hours

**Priority 3: Implement ruby_exe (plus_spec)**
- Add subprocess execution to rubyspec_helper
- Effort: 1-2 hours

**Priority 4: Fix Proc storage (round_spec)**
- Debug Proc block storage/retrieval
- Effort: 3-6 hours

**Priority 5: Add FPE handling**
- Catch FPE signals gracefully
- Effort: 2-3 hours, fixes 4 specs

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
