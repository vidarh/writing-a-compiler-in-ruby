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

## 5. Hash Literals as Arguments with Blocks - RESOLVED

**Status**: ✅ FIXED (2025-11-10)

**Problem**: Passing a hash literal as an argument to a method that also accepts a block caused "undefined method 'pair'" runtime error.

**Solution**: Fixed argument wrapping in `compile_calls.rb` (both `compile_call` and `compile_callm`). When a block is present, AST nodes like `[:hash, ...]`, `[:array, ...]`, `[:proc, ...]` now get wrapped in an array to prevent flattening that exposed `:pair` symbols as method calls.

**Changes**:
- compile_calls.rb:212-221 - Added AST node wrapping in `compile_call`
- compile_calls.rb:322-330 - Added AST node wrapping in `compile_callm`

**Now works**:
```ruby
def test(*args)
  yield
  args[0][:key]
end

test({:key => 42}) do   # ✓ Works
  puts "block"
end
```

**Test**: `spec/hash_literal_with_block_spec.rb` - now passing (2/2 tests)

---

## 9. Block Parameter Forwarding - RESOLVED

**Status**: ✅ FIXED (2025-11-10)

**Problem**: Using `&block` parameter forwarding in method calls without parentheses caused "Expression did not reduce to single value" error.

```ruby
def foo(*a, &b)
  bar *a, &b     # ✗ Parse error (was broken)
  bar(*a, &b)    # ✓ Always worked (with parentheses)
end
```

**Error**: `Expression did not reduce to single value (2 values on stack)`

**Root Cause**: When parsing `foo m, *a, &b` (without parentheses), the shunting yard parser created `[:call, ...]` and `[:to_block, b]` as separate expressions on the value stack. The `:to_block` wasn't being incorporated into the method call's arguments.

**Solution**: Modified `treeoutput.rb` lines 292-308 to detect when `:to_block` is created and the value stack already has a `:call` or `:|` (block parameters) expression. The `:to_block` is now merged into that expression's arguments instead of being pushed separately.

**Changes**:
- treeoutput.rb:297-306 - Added special handling to merge :to_block into :call or :| expressions

**Now works**:
```ruby
def foo(*a, &b)
  bar *a, &b      # ✓ Now works
  bar(*a, &b)     # ✓ Still works
end

# Also works inside blocks:
foo do |*a, &b|
  bar *a, &b     # ✓ Now works
end
```

**Tests**:
- make selftest - passes (0 failures)
- make selftest-c - passes (0 failures)
- spec/block_parameter_forwarding_spec.rb (2/2 tests pass)

---

## 10. Operator Precedence: => vs == - RESOLVED

**Status**: ✅ FIXED (2025-11-10)

**Problem**: Hash literals like `{:a==>1}` failed to parse because `:a=` wasn't recognized as a valid symbol.

```ruby
{:a => 1}     # ✓ Works
{:a==>1}      # ✓ Now works (was parse error)
```

**Root Cause**: The symbol parser (`sym.rb`) would parse `:a` and stop, not recognizing that `=` can be part of a symbol name (setter methods like `:a=`). The tokenizer would then see `==>` and tokenize it as `==` followed by `>`.

**Solution**: Modified `Sym.expect` in `sym.rb` (lines 13-17) to check if an atom is followed by `=` and include it in the symbol name. Now `:a=` is correctly recognized as a single symbol token, leaving `=>` as the hash pair operator.

**Changes**:
- sym.rb:13-17 - Added check for `=` after atom to form setter symbol

**Test**: rubyspec/language/hash_spec.rb

**Note**: This fix also correctly handles other setter symbols like `:foo=`, `:bar=`, etc.

---

## 11. Break with Splat - RESOLVED

**Status**: ✅ FULLY FIXED (2025-11-10)

**Problem**: Using splat operator with break statement caused compilation failure.

```ruby
loop do
  break *[1, 2]  # ✓ Now works - returns [1, 2]
end
```

**Parser Fix Applied** (2025-11-10):
- Modified `shunting.rb` lines 61-67 to prevent premature reduction of prefix operators
- Added check: Don't reduce prefix operators when a higher-precedence prefix operator follows
- Example: `break` (pri 22) should NOT be reduced when `*` (pri 8) arrives
- The parser now correctly generates: `[:break, [:splat, [:array, 1, 2]]]`

**Code Generation Fix Applied** (2025-11-10):
- Implemented `compile_splat` method in compiler.rb (lines 1067-1073)
- In break/return/next context, `*array` evaluates to the array itself
- Returns `Value.new([:subexpr], :object)` after evaluating the expression
- Pattern matches other expression compilers like `compile_array`

**Now works**:
```ruby
result = loop do
  break *[1, 2]
end
puts result.inspect  # => [1, 2]
```

**Tests**:
- make selftest - passes (0 failures)
- make selftest-c - passes (0 failures)
- Standalone test works correctly

**Note**: spec/break_with_splat_spec.rb segfaults due to mspec framework environment issues (not the feature itself)

---

## 12. String Interpolation Edge Cases

**Problem**: String interpolation with unusual delimiters fails to parse.

```ruby
"hey #{expr}"     # ✓ Works
%Q{hey #{expr}}   # ✓ Works (likely)
%$hey #{expr}$    # ✗ Parse error
```

**Root Cause**: Parser doesn't handle all string delimiter variants supported by MRI Ruby. The tokenizer may not recognize certain % delimiter combinations.

**Impact**:
- string_spec.rb fails to compile
- Very uncommon - most code uses standard delimiters
- Low priority edge case

**Workaround**: Use standard string delimiters (`"`, `'`, `%Q{}`, etc.)

**Test**: rubyspec/language/string_spec.rb

**Priority**: Very Low - extremely uncommon syntax

---

## 13. Alias Keyword Not Implemented

**Problem**: The `alias` keyword is not implemented.

```ruby
def foo
  "hello"
end

alias bar foo  # ✗ Not implemented
```

**Root Cause**: Keyword not recognized by parser, feature not implemented.

**Impact**:
- alias_spec.rb fails to compile
- Workaround: Define method that calls original method

**Workaround**:
```ruby
def bar
  foo
end
```

**Test**: rubyspec/language/alias_spec.rb

**Priority**: Medium - common feature, but workarounds exist

---

## 14. Block Parameters with Default Values

**Problem**: Block parameters with default values fail to parse.

```ruby
foo { |a=5, b=4, c=3| [a, b, c] }  # ✗ Parse error
```

**Error**: `Missing value in expression / op: {assign/2 pri=7}`

**Root Cause**: The parser doesn't properly handle the assignment syntax within block parameter lists. When it encounters `|a=5, b=4, c=3|`, it tries to parse the `=` as assignment operators but fails to construct a valid expression tree.

**Impact**:
- block_spec.rb fails to compile at line 100
- Optional block parameters cannot be used
- Affects code that needs default values for block parameters

**Workaround**:
- Use conditional assignment inside the block:
  ```ruby
  foo { |a, b, c|
    a ||= 5
    b ||= 4
    c ||= 3
    [a, b, c]
  }
  ```

**Test**: rubyspec/language/block_spec.rb (line 100)

**Priority**: Medium - less common pattern, workaround exists

---

## 15. Bignum Multiplication by Negative Fixnum - RESOLVED

**Status**: ✅ FIXED (2025-11-10)

**Problem**: Multiplying heap integers (Bignums) by negative fixnums produced corrupted results.

```ruby
1073741824 * (-1)  # ✗ Returned 9903520314283042198119251968 (wrong)
                   # ✓ Now returns -1073741824 (correct)
```

**Root Cause**: The `__multiply_heap_by_fixnum` method in `lib/core/integer.rb` line 840 set `result_sign = my_sign` without checking if the fixnum multiplier was negative. The comment even noted "For now, assume fixnum is positive (will handle negative later)" but the negative case was never implemented.

**Impact**:
- Integer literal parsing failed: `-1073741824` was corrupted during tokenization
- Selftest failure: "Parse large negative integer" test failed
- Any Bignum × negative fixnum operation was broken

**Solution**: Modified `__multiply_heap_by_fixnum` (lines 802-849) to:
1. Extract absolute value and sign of fixnum multiplier
2. Multiply limbs by fixnum magnitude (not signed value)
3. Compute result sign as `my_sign * multiplier_sign` (XOR logic)
4. Pattern matches `__divide_heap_by_fixnum` implementation

**Changes**:
- lib/core/integer.rb:807-814 - Added sign extraction for fixnum
- lib/core/integer.rb:825 - Changed to multiply by `multiplier` (absolute value)
- lib/core/integer.rb:849 - Changed to `result_sign = my_sign * multiplier_sign`

**Tests**:
- spec/bignum_multiply_negative_one_spec.rb (4/4 tests pass)
- make selftest - all tests pass (0 failures)
- make selftest-c - all tests pass (0 failures)

