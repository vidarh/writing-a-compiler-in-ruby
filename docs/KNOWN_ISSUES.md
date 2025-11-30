# Known Issues

**Last Updated**: 2025-11-30

## Current State Summary

**Selftest**: All passing (selftest and selftest-c)

**Language Specs**: ~78 files
- PASSED: 3 files (and_spec, not_spec, unless_spec)
- FAILED: ~23 files (run but fail assertions)
- CRASHED: ~52 files (segfaults/hangs)
- COMPILE FAIL: 0 files (all specs compile)

## Recent Fixes (2025-11-30)

1. **Array#<< growth condition** (ba819c8) - Fixed inverted condition that caused memory exhaustion
2. **Postfix if/unless returns nil** (2dee682) - `(x if false)` now returns nil, not false
3. **Parallel assignment** (cbd40e0) - `a, b, c = 1, 2, 3` now works correctly
4. **Scope resolution (::) as prefix** (17eab49) - `::Object` now works after whitespace
5. **Block params with defaults** (8ccfcbd) - `{ |a=99| }` correctly applies defaults
6. **Break/next newline handling** (8c97401) - `break\nputs x` now parses as two statements
7. **Hash spread operator (**)** - `{**h, a: 1}` now parses correctly (was exponentiation)

---

## Active Issues

### 1. super() Uses Wrong Superclass (CRITICAL)

**Impact**: Infinite recursion in class hierarchies deeper than 2 levels

**Problem**: `super` uses `obj.class.superclass` instead of the defining class's superclass.

```ruby
class A; def foo; "A"; end; end
class B < A; def foo; super; end; end
class C < B; def foo; super; end; end
C.new.foo  # Infinite loop: B#foo calls B#foo instead of A#foo
```

**Workaround**: Avoid `super` in deep hierarchies.

---

### 2. Lambda/Block Segfaults

**Impact**: ~16 specs crash during lambda/block execution

**Symptoms**: Segfaults in closure execution, often with invalid memory addresses.

**Minimal Repro** (loop with break inside block called via .call):
```ruby
def outer(&b)
  b.call
end

def test
  x = 0
  outer do
    loop do
      x += 1
      break if x >= 2
    end
  end
  puts x  # Never reached - segfault
end
test
```

**Root Cause Analysis**:
- Break from block inside `loop` corrupts %ebx (numargs register)
- Stack unwinding during break not restoring registers correctly
- After return to caller, stack adjustment uses corrupt %ebx value

**Affected specs**: block_spec, lambda_spec, proc_spec, loop_spec, and others

---

### 3. Classes in Lambdas - Runtime Segfault

**Status**: Compiles but segfaults at runtime

**Problem**: Classes defined inside lambdas get incorrect `Object__` prefix in assembly.

```ruby
l = lambda do
  class Foo; def test; 42; end; end
  Foo.new.test
end
l.call  # Segfault
```

---

### 4. Keyword Arguments - Partial Support

**Status**: Basic keyword args work, advanced features segfault

**Works**:
- `def foo(a:, b:)` - required kwargs
- `def foo(a: 42)` - optional kwargs
- `def foo(**kwargs)` - keyword rest

**Doesn't work**: keyword_arguments_spec still crashes

---

### 5. Compound Expression After If/Else

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
