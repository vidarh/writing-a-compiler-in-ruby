# Known Issues

## 1. Control Flow as Expressions (BLOCKER)

**Problem**: Control structures work as expression values in assignments (`x = if...`) but not in other contexts (method chaining, arithmetic, array literals).

```ruby
x = if true; 42; end        # ✓ Works
if true; 42; end.to_s       # ✗ Parse error
```

**Root Cause**: Control structures at statement level don't go through shunting yard, so operators after them have no left-hand value.

**Impact**: Blocks MANY language specs - primary cause of 60 compilation failures

**Solution**: Architectural parser redesign - move all control flow through shunting yard. Complex.

**Test**: spec/control_flow_expressions_spec.rb

**Details**: See control_flow_as_expressions.md for full architectural analysis.

---

## 2. Top-Level Blocks/Lambdas

**Problem**: Blocks and lambdas at top-level fail with "undefined method" for parameters.

```ruby
[1,2,3].each { |i| puts i }  # ✗ Fails at top-level
                              # ✓ Works inside methods
```

**Workaround**: Wrap all test code in methods. RubySpecs already do this.

**Impact**: Only affects top-level code, not actual program code.

---

## 3. Module include - IMPLEMENTED (with limitations)

**Status**: ✅ PARTIALLY FIXED (2025-11-08)

**Problem**: The `include` keyword was not implemented. Modules could not be included in classes.

**Solution**: Implemented runtime vtable copying via `__include_module(klass, mod)` function.

**How it works**:
1. During class definition, `include ModuleName` calls `__include_module(self, ModuleName)`
2. At runtime, `__include_module` loops through module's vtable (slots 6 to __vtable_size)
3. For each slot, if class slot is uninitialized (points to __base_vtable method_missing thunk), copy module's slot
4. This preserves class methods and supports multiple includes (first defined wins)

**Now works**:
```ruby
module TestModule
  def test_method
    42
  end
end

class TestClass
  include TestModule  # ✓ Works - methods copied at runtime
end

obj = TestClass.new
obj.test_method  # ✓ Returns 42
```

**Limitations**:
- **Ordering issue**: If a class includes a module that's defined later in the file, include silently fails (module constant is still 0/null)
  - Example: Integer includes Comparable, but Comparable is defined after Integer in compilation order
  - Workaround: `__include_module` checks if mod==0 and returns early to prevent crash
  - Proper fix: Dependency analysis and reordering of class initialization
- Transitive includes work (if module A includes module B, and class C includes A, C gets methods from both)
- No support for `prepend` or `extend`
- No `included` callback support

**Impact**: Code duplication still needed in some cases due to ordering issue, but basic include works

---

## 4. Toplevel Constant Paths

**Problem**: `class ::Foo` syntax causes selftest-c to segfault.

**Status**: Feature reverted (commit 11b8c88).

**Why Needed**: RubySpecs use `class ::Object` to avoid local constant conflicts.

**Details**: See toplevel_constant_paths_issue.md.

---

## 5. Integer::MIN Literal

**Problem**: Value `-1073741824` (exactly at fixnum boundary) corrupts during self-compilation, produces incorrect huge negative number.

**Workaround**: Constant commented out in lib/core/integer_base.rb and lib/core/integer.rb.

**Root Cause**: Unknown. Likely bug in literal parsing or emission for boundary values.

**To Fix**: Debug tokens.rb (Tokens::Int.expect) or compiler constant emission.

---

## 6. Lambda .() Call Syntax - RESOLVED

**Status**: ✅ FIXED (2025-11-08)

**Problem**: The `.()` syntax for calling lambdas/procs was not implemented.

**Solution**: Modified `tokens.rb` line 741-743 to detect when `.` is followed by `(` and insert `:call` as the method name. This handles `.()` at the tokenizer level, before it reaches the shunting yard.

**How it works**:
```ruby
# In tokens.rb, after seeing . (callm operator):
if !res && @s.peek == ?(
  res = :call  # Insert :call as method name when .() detected
end
```

**Now works**:
```ruby
l = lambda { 42 }
l.call        # ✓ Works
l[]           # ✓ Works
l.()          # ✓ Works (as of 2025-11-08)
l.(21)        # ✓ Works with arguments
l.(40, 2)     # ✓ Works with multiple arguments
```

**Tests**: spec/lambda_dot_paren_spec.rb (3 tests pass)

**Note**: Proc.new crashes (pre-existing bug unrelated to .() implementation - also crashes with .call)

---

## 7. Float Support Limited

**Problem**: Float class exists but has minimal implementation (mostly stubs).

**Impact**:
- Integer spec crashes: fdiv_spec, round_spec, times_spec
- Integer spec failures: Many comparisons with Float literals fail
- Division by Float not supported

**Root Cause**: Float is not fully implemented - no floating-point arithmetic

**Priority**: Medium - affects many integer spec failures but not blockers

---

## 8. Bignum Modulo Precision Loss

**Problem**: Modulo operation loses precision for very large bignum values.

**Example**:
```ruby
9999 % 99              # => 0 ✓ (correct)
9999**99 % 99          # => 95 ✗ (wrong - should be 0)
```

**Root Cause**: The modulo operation uses `a % b = a - (a/b)*b` for bignum values. Either division or multiplication is losing precision for very large numbers (9999**99).

**Impact**:
- gcd_spec.rb: 10/12 passing (2 bignum failures)
- lcm_spec.rb: Similar failures with large numbers
- Any bignum arithmetic with very large values may have precision issues

**Investigation**:
- `9999**99 / 99` appears to work
- `(9999**99 / 99) * 99` ≠ 9999**99` (off by 95)
- Could be division rounding error or multiplication overflow
- Requires deep debugging of bignum limb arithmetic

**Test Case**: See test_modulo_bug.rb (created during investigation)

**Priority**: Medium - affects edge cases with very large numbers only

