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

**Test**: spec/control_flow_expressions.rb

**Details**: See control_flow_as_expressions.md for full architectural analysis.

---

## 2. Ternary Operator Bug

**Problem**: When condition is a variable that's `false`, returns `false` instead of else value. Literal `false` works correctly.

```ruby
false ? "WRONG" : "CORRECT"          # ✓ Works - returns "CORRECT"
var = false
var ? "WRONG" : "CORRECT"            # ✗ Bug - returns false
```

**Workaround**: Use if/else instead of ternary operator.

**Test**: spec/ternary_operator_bug.rb - reproduces bug consistently

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

---

## 6. Lambda .() Call Syntax Not Supported

**Problem**: The `.()` syntax for calling lambdas/procs is not implemented.

```ruby
l = lambda { 42 }
l.call        # ✓ Works
l.()          # ✗ Parse error - not supported
```

**Impact**: Blocks lambda_spec and other specs using this syntax

**Workaround**: Use `.call` instead of `.()`

**Test**: spec/lambda_call_syntax.rb

---

## 7. Float Support Limited

**Problem**: Float class exists but has minimal implementation (mostly stubs).

**Impact**:
- Integer spec crashes: fdiv_spec, round_spec, times_spec
- Integer spec failures: Many comparisons with Float literals fail
- Division by Float not supported

**Root Cause**: Float is not fully implemented - no floating-point arithmetic

**Priority**: Medium - affects many integer spec failures but not blockers
