# Ruby Compiler TODO

**Last Updated**: 2025-11-30

## Test Status

**Selftest**: All passing (selftest and selftest-c)

**Language Specs**: ~78 files
- PASSED: 3 files (4%)
- FAILED: ~23 files (29%)
- CRASHED: ~52 files (67%)
- COMPILE FAIL: 0 files

---

## Priority 1: Medium Effort (Days)

### 1.1 Lambda/Block Segfaults

**Impact**: ~16 specs crash

**Investigation areas**:
1. Global variable in closure (`$var = nil` crashes)
2. NULL pointer dereferences
3. Invalid memory addresses

**Specs**: block_spec, lambda_spec, proc_spec, loop_spec

---

### 1.2 Classes in Lambdas

**Problem**: Classes defined in lambdas get wrong name prefix.

**Fix**: Scope-walking logic for class naming needs to handle lambda scopes.

---

### 1.3 super() Implementation

**Impact**: super_spec, any deep class hierarchies

**Problem**: Uses `obj.class.superclass` instead of method's defining class.

**Fix**: Track defining class in method dispatch, use for super lookup.

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

## Recently Completed (2025-11-30)

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
