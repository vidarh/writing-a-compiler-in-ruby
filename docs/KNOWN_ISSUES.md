# Known Issues

**Last Updated**: 2026-02-10

## Current State Summary

**Selftest**: All passing (selftest and selftest-c)

**Language Specs**: 78 files
- Passed: 3 files (and_spec, not_spec, unless_spec)
- Failed: 28 files (run but fail assertions)
- Crashed: 47 files (segfaults/hangs)
- Compile fail: 0 files (all specs compile)

**Individual Test Cases**: 994 total, 272 passed, 705 failed, 17 skipped, 27% pass rate

## Recent Fixes (2025-12-01)

1. **Break from blocks crash** - Top-level blocks with `break` no longer crash
   - Root cause: After unwinding stack frames, %ebx was restored from wrong frame
   - Fix: Save %ebx to %edx before unwinding loop, restore after
   - Note: Break still exits DEFINER instead of YIELDER (not Ruby-compliant)

2. **Super in deep hierarchies** - `super` now works correctly in A < B < C chains
   - Root cause: Was using `self.class.superclass` instead of defining class's superclass
   - Fix: Pass defining class name and look up its superclass directly
   - Remaining edge case: `super()` in `define_method` blocks still unsupported (needs method name from define_method arg)

3. **Hash with nil keys** - `{nil => value}[nil]` now works correctly
   - Root cause: nil was used as both valid key AND empty slot marker
   - Fix: Added special handling to iterate/lookup nil keys via linked list

4. **Classes in lambdas** - Simple classes defined inside lambdas now compile and run correctly

## Previous Fixes (2025-11-30)

1. **Array#<< growth condition** (ba819c8) - Fixed inverted condition that caused memory exhaustion
2. **Postfix if/unless returns nil** (2dee682) - `(x if false)` now returns nil, not false
3. **Parallel assignment** (cbd40e0) - `a, b, c = 1, 2, 3` now works correctly
4. **Scope resolution (::) as prefix** (17eab49) - `::Object` now works after whitespace
5. **Block params with defaults** (8ccfcbd) - `{ |a=99| }` correctly applies defaults
6. **Break/next newline handling** (8c97401) - `break\nputs x` now parses as two statements
7. **Hash spread operator (**)** - `{**h, a: 1}` now parses correctly (was exponentiation)

---

## Active Issues

### 1. Break from Blocks - Wrong Return Target (Partial)

**Status**: No longer crashes, but semantics are not Ruby-compliant

**2025-12-01 Update**: Resolved crash when break is called from top-level blocks.
The issue was that after unwinding stack frames, %ebx was being restored from
the wrong frame (target frame instead of source frame). Solution: Save %ebx to %edx
before the unwinding loop, restore after.

**Remaining Issue**: `break` behaves like `return` - exits the DEFINER instead of the YIELDER.

In Ruby:
- `break` should exit the method that YIELDED to the block
- `return` should exit the method that DEFINED the block
- Current implementation has `break` behaving like `return`

**Example of wrong behavior**:
```ruby
def yielder
  yield
  puts "after yield"  # MRI: does NOT print (break exits yielder)
end

def test
  yielder { break }
  puts "after yielder"  # MRI: prints this
end
test
# MRI output: "after yielder"
# Our output: nothing (exits test entirely because break acts like return)
```

**Root Cause**:
- Blocks capture `__env__[0]` = frame pointer where block was CREATED
- `break` unwinds to `__env__[0]` which is the CREATOR's frame
- Should unwind to YIELDER's frame instead

**What works**:
- `return` from blocks (correctly returns from defining method)
- `break` inside `while`/`until` loops (uses ControlScope, not __env__)
- Break no longer crashes (resolved 2025-12-01)

**What doesn't work correctly**:
- `break` exits the definer instead of the yielder (wrong Ruby semantics)

**Previous fix attempts** (documented for reference):

1. **Two-slot env approach** (self-compilation crashes):
   - Add `__breakframe__` at `__env__[1]`, keep `__stackframe__` at `__env__[0]`
   - `Proc#call` sets `@env[1]` to `caller_stackframe` before calling block
   - Break reads `__env__[1]` instead of `__env__[0]`
   - **BLOCKED**: Self-compilation crashes due to env layout change

2. **Global variable approach** (crashes):
   - Store break target in global variable, set by `Proc#call`
   - Causes crashes for unknown reasons

**Affected specs**: block_spec, lambda_spec, proc_spec, loop_spec, and others

---

### 2. Keyword Arguments - Partial Support

**Status**: Basic keyword args work, advanced features segfault

**Works**:
- `def foo(a:, b:)` - required kwargs
- `def foo(a: 42)` - optional kwargs
- `def foo(**kwargs)` - keyword rest

**Doesn't work**: keyword_arguments_spec still crashes

---

### 3. Compound Expression After If/Else

**Problem**: Compound expressions immediately after if/else can corrupt variables.

```ruby
if condition
  # branch
end
result = obj.method1 + obj.method2  # May crash
```

**Workaround**: Break into separate statements.

---

## Known Limitations (Cannot Fix)

1. **eval() with dynamic strings** - AOT compilation cannot evaluate runtime strings
2. **Float** - Not implemented (~17 test failures)
3. **Command execution** - Backticks/`%x{}` not implemented (~8 failures)
4. **Rational/Complex** - Not implemented

---

## Test Framework Issues

Some specs fail due to test framework dependencies:
- `require $spec_filename` - Dynamic require not supported
- `ScratchPad` - Test framework class not available
- `fixture()` - Test helper not implemented

---

## References

- **TODO.md** - Prioritized task list
- **DEBUGGING_GUIDE.md** - Debugging techniques
