# Known Issues

## 1. super() Uses Object's Class Instead of Method's Defining Class (CRITICAL BUG)

**Problem**: `super` incorrectly uses the object's class to find the superclass, rather than the defining class of the current method. This causes infinite recursion when a subclass calls a superclass method that uses `super`.

```ruby
class A
  def initialize(x)
    puts "A#initialize: #{x}"
  end
end

class B < A
  def initialize(x)
    puts "B#initialize: #{x}"
    super(x)  # Should call A#initialize
  end
end

class C < B
  def initialize(x)
    puts "C#initialize: #{x}"
    super(x)  # Should call B#initialize
  end
end

C.new("test")
# Output:
# C#initialize: test
# B#initialize: test
# B#initialize: test    <- BUG: super in B calls B again!
# B#initialize: test
# ... infinite recursion
```

**Root Cause**: The `super` implementation looks up the superclass using `obj.class.superclass` instead of using the defining class of the method where `super` appears.

**Impact**: Any code using `super` in a class hierarchy deeper than 2 levels will infinite loop. Most standard library subclasses work around this by avoiding `super`.

**Workaround**: Avoid calling `super()` in initialize methods. For Exception subclasses, override `message` and set the message directly without calling `super(message)`.

**Test**: test_super_bug.rb

---

## 2. Control Flow as Expressions - RESOLVED

**Status**: ✅ FIXED (2025-11-10)

**Solution**: Modified shunting.rb:89-110 to parse if/while/unless/until as statement expressions when in prefix position, unless appearing after a prefix operator (where they're modifiers). Also removed :lambda from tokenizeradapter.rb escape_tokens and added to shunting.rb non-operator keyword handling.

**Changes**:
- shunting.rb:91 - Changed condition from `opstate == :prefix && ostack.length == 0` to `opstate == :prefix && (ostack.empty? || ostack.last.type != :prefix)`
- tokenizeradapter.rb:15-20 - Removed :lambda from @escape_tokens
- shunting.rb:222,230 - Added :lambda to statement keyword list
- operators.rb:81-87 - Added unless_mod and until_mod operators with right_pri=1

**Test**: spec/control_flow_expressions_spec.rb - now passing

**Note**: Still doesn't support method chaining on control flow results (e.g., `if true; 42; end.to_s`) - requires more complex architectural changes.

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

---

## 5. Hash Literals as Arguments with Blocks

**Problem**: Passing a hash literal as an argument to a method that also accepts a block causes a runtime error.

```ruby
def test(*args)
  yield
  args[0][:key]
end

test({:key => 42}) do   # ✗ Runtime error
  puts "block"
end
```

**Error**: `undefined method 'pair' for Object`

**Root Cause**: Hash construction appears to have issues when combined with block passing. The hash literal compiles successfully but accessing it at runtime fails.

**Impact**:
- platform_is/platform_is_not guards don't work with c_long_size parameters
- Any hash literal passed to a method with a block will fail at runtime
- Workaround: Preprocessor strips hash arguments in run_rubyspec

**Workaround**:
- `run_rubyspec` script preprocesses specs to convert problematic patterns
- `platform_is c_long_size: 64 do` → `if false # SKIPPED: 64-bit test`
- Create hash in variable first, then pass variable (may work)

**Test**: `spec/hash_literal_with_block_spec.rb`

**Priority**: Medium - affects testing infrastructure, workarounds in place

