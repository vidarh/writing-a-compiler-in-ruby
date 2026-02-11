# Ruby Compiler TODO

**Last Updated**: 2026-02-10

## Test Status

**Selftest**: All passing (selftest and selftest-c)

**Language Specs**: 78 files
- Passed: 3 files (4%)
- Failed: 28 files (36%)
- Crashed: 47 files (60%)
- Compile fail: 0 files

**Individual Test Cases**: 994 total, 272 passed, 705 failed, 17 skipped, 27% pass rate

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

### 1.2 super() in define_method

**Remaining edge case**: `define_method(:name) { super() }` needs method name from define_method argument, not scope lookup. Main super() implementation is complete.

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

## Completed

- Break crash fix, super in deep hierarchies, super in blocks, classes in lambdas (2025-12-01)
- Array#<< growth, postfix if/unless nil, parallel assignment, :: prefix, block param defaults, break/next newlines, hash spread (2025-11-30)

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
