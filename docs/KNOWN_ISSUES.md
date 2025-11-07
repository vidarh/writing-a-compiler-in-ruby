# Known Issues

## 1. Control Flow as Expressions (BLOCKER)

**Problem**: Control structures work as expression values in assignments (`x = if...`) but not in other contexts (method chaining, arithmetic, array literals).

```ruby
x = if true; 42; end        # ✓ Works
if true; 42; end.to_s       # ✗ Parse error
```

**Root Cause**: Control structures at statement level don't go through shunting yard, so operators after them have no left-hand value.

**Impact**: Blocks 5+ language specs (metaclass_spec, symbol_spec, unless_spec, while_spec, etc.)

**Solution**: Architectural parser redesign - move all control flow through shunting yard. Complex.

**Details**: See control_flow_as_expressions.md for full architectural analysis.

---

## 2. Ternary Operator Bug

**Problem**: When condition is false, `cond ? true_val : false_val` returns `false` instead of `false_val`.

```ruby
result = false ? "WRONG" : "CORRECT"
# result is false, not "CORRECT"
```

**Workaround**: Use if/else instead of ternary operator.

**Discovered**: During selftest-c debugging (compile_class.rb:40).

---

## 3. Top-Level Blocks/Lambdas

**Problem**: Blocks and lambdas at top-level fail with "undefined method" for parameters.

```ruby
[1,2,3].each { |i| puts i }  # ✗ Fails at top-level
                              # ✓ Works inside methods
```

**Workaround**: Wrap all test code in methods. RubySpecs already do this.

**Impact**: Only affects top-level code, not actual program code.

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
