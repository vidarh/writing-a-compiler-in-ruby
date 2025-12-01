# Ruby Compiler TODO

**Last Updated**: 2025-12-01

## Test Status

**Selftest**: All passing (selftest and selftest-c)

**Language Specs**: ~78 files
- PASSED: 3 files (4%)
- FAILED: ~23 files (29%)
- CRASHED: ~52 files (67%)
- COMPILE FAIL: 0 files

---

## Priority 1: Medium Effort (Days)

### 1.1 Break from Blocks - Wrong Return Target (Partially Fixed)

**Status**: No longer crashes, but semantics not Ruby-compliant

**2025-12-01 Fix**: Fixed crash when break is called from top-level blocks.
The issue was that after unwinding stack frames, %ebx was restored from the
wrong frame. Fix: Save %ebx to %edx before unwinding, restore after.

**Remaining issue**: `break` still exits DEFINER instead of YIELDER (wrong Ruby semantics).

**Ruby semantics**:
- `break` should exit the method that YIELDED to the block
- `return` should exit the method that DEFINED the block
- Current implementation has both behave like `return`

**Previous fix attempts** (blocked):
1. Two-slot env: Shifts `__closure__` index, crashes self-compilation
2. Global variable: Crashes for unknown reasons

**Specs**: block_spec, lambda_spec, proc_spec, loop_spec

---

### 1.2 Classes in Lambdas - FIXED

**Status**: Now works correctly. Classes defined in lambdas compile and run.

---

### 1.3 super() Implementation - MOSTLY FIXED

**Fixed cases**:
- Deep class hierarchies (A < B < C) - super now correctly uses defining class
- Super inside blocks (yields) - correctly finds enclosing method name
- Super with class methods (self.foo) - works correctly

**Remaining edge case**:
- `define_method(:name) { super() }` - super in define_method blocks needs
  method name from define_method argument, not scope lookup

---

## Priority 2: Larger Features

### 2.1 Float Support

**Impact**: ~17 test failures

**Approach**: Implement Float class with IEEE 754 representation.

---

### 2.2 Command Execution

**Impact**: ~8 test failures

**Approach**: Implement backticks/`%x{}` via `fork`/`exec`.

---

### 2.3 Literal eval() Support

**Impact**: ~100 test failures (partial)

**Approach**: Transform `eval("literal string")` to inline lambda at compile time.

---

## Recently Completed (2025-12-01)

- Break crash fix - Top-level blocks with break no longer crash (%ebx restore fix)
- Super in deep hierarchies - Fixed to use defining class's superclass, not self.class.superclass
- Super in blocks - Fixed to find enclosing method name, not block function name

## Previously Completed (2025-11-30)

- Array#<< growth condition - Fixed inverted condition causing memory exhaustion
- Postfix if/unless returns nil - `(x if false)` now returns nil, not false
- Parallel assignment - `a, b, c = 1, 2, 3` now works correctly
- Scope resolution (::) as prefix - `::Object` now works after whitespace
- Block params with defaults - `{ |a=99| }` now applies defaults correctly
- Break/next newline handling - `break\nputs x` parses as two statements
- Hash spread operator (**) - `{**h, a: 1}` parses correctly (was exponentiation)

---

## Testing Commands

```bash
make selftest        # Must pass
make selftest-c      # Must pass
./run_rubyspec rubyspec/language/   # Language specs
```

## References

- **KNOWN_ISSUES.md** - Detailed bug documentation
- **DEBUGGING_GUIDE.md** - Debugging techniques
