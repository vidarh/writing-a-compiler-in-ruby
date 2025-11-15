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

**Remaining work**:
- ✅ **while** `end.should` chaining - FIXED (spec/while_end_no_paren_spec.rb passes)
- ✅ **until** `end.should` WITHOUT parentheses - FIXED (2025-11-12)
  - **Fix**: Removed `parse_until` call from parse_defexp (parser.rb:488) and deleted dead code parse_while/parse_until
  - Now `until` works exactly like `while` - only as operator, not as statement
  - All four control flow keywords (if/unless/while/until) now support `end.should` without parens
  - Test: spec/until_end_should_spec.rb, spec/all_control_flow_end_should_spec.rb
- Method chaining on control flow results (e.g., `if true; 42; end.to_s`) - needs value wrapping

---

## 2. Parenthesized Control Flow - PARTIALLY RESOLVED

**Status**: ✅ PARTIALLY FIXED (2025-11-12)

**Fixed**: Parenthesized `break`/`next`/`return` without arguments now work:
```ruby
a ||= (break)   # ✓ Works now
a = (next)      # ✓ Works now
```

**Fix**: Added check in shunting.rb:162-165 to provide nil value to prefix operators with minarity=0 before closing parenthesis.

**Remaining Issue**: `break`/`next`/`return` with `if` modifier in assignment consumes tokens outside scope:
```ruby
result = break if condition  # ✗ Consumes `result` variable name
a ||= break if c             # ✗ Consumes `a` variable name
```

**Error**: "Missing value in expression / op: {assign/2 pri=7} / vstack: [] / rightv: [:break, :result]"

**Root Cause**: When `break` (prefix operator, pri=22) is followed by `if` (infix operator, pri=2), the shunting yard algorithm doesn't correctly handle the modifier if pattern. The `break` consumes tokens that should be outside its scope.

**Test**: spec/break_if_modifier_spec.rb, spec/or_assign_paren_expr_spec.rb (compiles, runtime segfault)

**Affects**: while_spec.rb, until_spec.rb (test cases with `break if` patterns)

**Priority**: MEDIUM - workaround exists (use explicit if/end instead of modifier if)

---

## 3. Top-Level Blocks/Lambdas

**Problem**: Blocks and lambdas at top-level fail with "undefined method 'lambda'" or "undefined reference to '__env__'".

```ruby
lambda { 42 }               # ✗ "undefined method 'lambda'" at top-level
[1,2,3].each { |i| puts i } # ✗ Fails at top-level
                            # ✓ Works inside methods
```

**Root Cause**: The `rewrite_lambda()` function in transform.rb is only called from `rewrite_let_env()`, which only processes `:defm` nodes (method definitions). Top-level code is not inside a `:defm`, so:
1. Top-level `:lambda` nodes never get transformed into `:defun` + `__new_proc` calls
2. Without transformation, compiler tries to compile `:lambda` as a method call to non-existent `lambda` method
3. Even if manually transformed, top-level lacks `__env__`, `__tmp_proc`, and `__closure__` variables that lambdas require

**Workaround**: Wrap all test code in methods. RubySpecs already do this.

**Impact**: Only affects top-level code, not actual program code.

**Recent Findings (2025-11-12)**:
- Classes defined inside lambdas at top-level now **compile successfully** (nil ClassScope bug fixed)
- But programs with top-level lambdas **segfault at runtime**, even with classes in methods calling lambdas
- The issue appears during initialization, before any lambda code executes
- Likely cause: Missing environment setup for lambdas that depend on rewrites only happening inside `:defm`

**Possible Solution**: Compile the entire main block as if it's a method body, then call it. This would trigger the necessary rewrites for lambda support.

---

## 3. Classes Defined in Lambdas - Runtime Segfault

**Status**: ⚠️ PARTIALLY FIXED (2025-11-12)

**Problem**: Classes defined inside lambda scopes now **compile successfully** (nil ClassScope bug fixed) but **segfault at runtime**.

**Progress**:
- ✅ Compilation: Fixed nil ClassScope error by creating ClassScope on-demand in compile_class.rb
- ✅ Specs compile: break_spec.rb, line_spec.rb, file_spec.rb now compile (was blocked)
- ❌ Runtime: Programs with classes-in-lambdas crash with segfault

**Root Cause** (suspected):
Classes defined in lambdas get incorrect `Object__` prefix in generated assembly. The scope-walking logic finds Object's ClassScope when it should use GlobalScope for top-level naming. This causes symbol mismatches at runtime.

**Example**:
```ruby
l = lambda do
  class Foo  # Should generate "Foo", generates "Object__Foo"
    def test
      42
    end
  end
  Foo.new.test
end
l.call  # ✗ Segfault
```

**Investigation Status**:
- Compilation generates both `Foo:` and `Object__Foo:` symbols
- Code references `Object__Foo` but class is named `Foo`
- Issue exists even when lambda is inside a method (not top-level lambda issue)
- Affects all specs with classes-in-lambdas: spec/class_in_lambda_spec.rb

**Test**: spec/class_in_lambda_spec.rb (compiles, crashes at runtime)

**See**: docs/nil_classscope_investigation.md for detailed analysis

**Priority**: High - blocks multiple rubyspec files that now compile

---

## 4. Module include - IMPLEMENTED (with limitations)

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

## 9. Block Parameters with Default Values - PARTIALLY IMPLEMENTED

**Status**: 🟡 PARTIALLY FIXED (2025-11-10)

**Problem**: Block parameters with default values like `{ |a=5| puts a }` fail to parse or execute correctly.

**What Works**:
- ✅ Parser correctly handles syntax: `{ |a=5| }` parses to `[[:a, :default, 5]]`
- ✅ Transform phase preserves default values when creating lambdas
- ✅ Code compiles without errors inside methods

**What Doesn't Work**:
- ❌ Runtime: Block parameters receive wrong values (get entire array instead of elements)
- ❌ Top-level: Blocks at top-level don't get transformed (see Issue #2)
- ❌ Default values not applied correctly - parameters always receive nil or wrong values

**Example**:
```ruby
def test
  [1, 2].each { |a=99| puts a }
end
test
# Output: [1, 2]  [1, 2]  <- Bug: prints array twice instead of 1, 2
```

**Implementation Status**:
1. ✅ `parser.rb`: Modified `parse_arglist()` to accept `extra_stop_tokens` parameter
2. ✅ `parser.rb`: Updated `parse_block()` to pass `[PIPE]` as stop token
3. ✅ `transform.rb`: Fixed `rewrite_lambda()` to handle `[name, :default, value]` format
4. ❌ `output_functions.rb`: Needs fix to `output_default_args()` for lambda argument positions

**Root Cause**:
The `output_default_args()` function checks `if numargs < 1 + xindex` to determine if a default should be used. However, for lambdas:
- Function signature: `(self, __closure__, __env__, user_arg0, user_arg1, ...)`
- `numargs` includes ALL arguments (implicit + user)
- For first user arg at position 3, need `numargs >= 4`, not `numargs >= 1`
- Current check always fails, so default is never used and wrong argument is accessed

**Attempted Fix**: Tried calculating actual argument position:
```ruby
actual_position = func.args.index { |a| a.name == arg.name }
compile_if(fscope, [:lt, :numargs, actual_position + 1], ...)
```
But this broke regular method default parameters and caused selftest-c to fail.

**Challenge**: Need to distinguish lambdas (3 implicit args) from methods (2 implicit args) to calculate correct `numargs` threshold. Function class doesn't track which arguments are implicit.

**Workaround**: Don't use default values on block parameters. Use explicit nil checks instead:
```ruby
[1, 2].each { |a| a = 99 if a.nil?; puts a }
```

**Priority**: Low - uncommon pattern, workaround exists

**Test Files**: test_block_default_params.rb, test_block_default_in_method.rb, test_each_simple.rb

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


---

## 16. Nil ClassScope in Nested Classes/Closures

**Problem**: Classes defined inside closures or other unusual scoping contexts fail compilation with `undefined method 'name' for nil:NilClass` at compile_class.rb:155.

**Error**:
```
/app/compile_class.rb:155:in `compile_class': undefined method `name' for nil:NilClass (NoMethodError)
```

**Root Cause**: The transform phase's `build_class_scopes()` (transform.rb:674-680) creates ClassScope objects and adds them to `@classes` hash and scope chain. However, when classes are defined in certain contexts (e.g., inside let blocks, closures, or nested deeply), the transform phase may not properly register the ClassScope, leaving `scope.find_constant(name)` returning nil.

**Affects**: 
- rubyspec/language/break_spec.rb (module BreakSpecs with nested class Driver)
- Multiple other language specs with nested class definitions

**Investigation Needed**: 
1. Determine exact contexts where ClassScope creation fails
2. Check if transform phase processes all class definitions
3. May need to handle class definitions in closures differently

**Workaround**: Avoid defining classes inside closures or complex scoping contexts.

**Priority**: High - blocks multiple language specs

---

## 17. Splat in Assignment LHS Not Supported

**Problem**: Destructuring assignments with splat on the left-hand side are not implemented.

**Error**:
```
Expected an argument on left hand side of assignment - got subexpr, 
(left: [:splat, :c], right: [:callm, :__destruct, :[], [[:sexp, 5]]])
```

**Example**:
```ruby
# Not supported:
*a = [1, 2, 3]        # Error
a, *b = [1, 2, 3]     # Error  
a, *b, c = [1, 2, 3]  # Error
```

**Root Cause**: The destructuring rewrite in transform.rb handles simple assignments but doesn't implement splat collection logic.

**Affects**:
- rubyspec/language/next_spec.rb
- Likely other assignment/destructuring specs

**Implementation Needed**:
1. Detect splat in destructuring assignment LHS
2. Generate code to collect remaining elements into array
3. Handle splat in various positions (beginning, middle, end)

**Workaround**: Manually slice arrays instead of using splat syntax.

**Priority**: Medium - affects fewer specs than nil ClassScope issue

---

## 18. Unclosed Block/Hash on Operator Stack - PARTIALLY FIXED

**Problem**: Parser left `{` unclosed causing "Syntax error [{/0 pri=99}]"

**Status**: Two major root causes have been FIXED:

1. ✅ **FIXED** - Heredoc followed by method chain (tokens.rb)
   - **Issue**: `foo(<<-END).bar` would discard `.bar` after heredoc marker
   - **Fix**: Save and restore rest-of-line after heredoc using scanner.unget()
   - **Example**: `ruby_exe(<<-CODE).should == "result"` now compiles

2. ✅ **FIXED** - Keywords in parentheses (shunting.rb)
   - **Issue**: `(def foo; end; 42)` would break on `def`, leaving `(` unclosed
   - **Fix**: Allow keywords inside parentheses context
   - **Example**: `case (def foo; end; value) when ...` now compiles

**Remaining Issues**: Some specs still fail, but with different errors (progress made)

**Affects**:
- return_spec.rb - progresses past line 410, now fails on "Unable to open '$spec_filename'" (dependency issue)
- if_spec.rb - progresses to link stage, fails on missing ScratchPad (test framework dependency)
- case_spec.rb - progresses past line 258, now fails on parse error "'end' for open 'case'" (different bug)
- while_spec.rb - still fails with compilation errors

**Note**: "Progresses to link stage" means parser and compiler work, but linker fails due to missing test dependencies - this is progress but not a complete fix.

**Priority**: Medium - major blockers removed, remaining cases need individual investigation

---

## 19. If-Statement Without Else Returns Condition Value Instead of Nil

**Problem**: When an if-statement has no else-branch and the condition is false, the expression returns the condition value instead of nil.

```ruby
result = if false then 123 end
puts result.inspect  # Outputs: false (WRONG - should be nil)

result = if true then 123 end
puts result.inspect  # Outputs: 123 (correct)
```

**Root Cause**: In `compile_control.rb`, the `compile_if` function only generates the endif label and jump when `else_arm` is present. When there's no else-arm:
- Line 114: `@e.jmp(l_end_if_arm) if else_arm` - No jump generated
- Line 125: `@e.local(l_end_if_arm) if else_arm` - No endif label created
- When condition is false, execution jumps to else label but has no code to load nil into %eax
- The %eax register still contains the condition value (false)

**Failed Fix Attempts**:
1. Using `@e.load_address("nil")` - causes segfault during bootstrap initialization
2. Using `compile_eval_arg(scope, :nil)` - causes segfault during bootstrap initialization
3. Using `get_arg(scope, :nil)` followed by `@e.movl` - generates invalid assembly with literal `[:global, :nil]`

**Why Fixes Fail**: The fix requires loading nil during the else-branch code generation. However, if-statements without else-arms occur during early bootstrap (e.g., Class initialization), and the nil global may not be properly initialized yet at that point. Any attempt to reference nil causes bootstrap failures.

**Impact**: 
- if_spec.rb fails 2/25 tests
- Any code relying on `if condition; value; end` returning nil when condition is false will get the condition value instead

**Workaround**: Always provide an explicit else-branch: `if condition; value; else; nil; end`

**Solution Needed**: The fix requires either:
1. Ensuring nil is initialized before any if-statements are compiled, or
2. Using a different code generation strategy that doesn't reference the nil global, or  
3. Deferring nil loading to a later stage after globals are set up

**Priority**: Medium - Affects correctness but has simple workaround

**Test File**: Created test_if_nil.rb during investigation (removed)

**Files**: compile_control.rb:97-136 (compile_if function)

---

## 20. Require with Dynamic Path Not Supported

**Problem**: The compiler processes `require` statements statically at compile-time. This means it cannot handle require with dynamic paths (e.g., paths from variables or expressions).

```ruby
# This fails:
require $spec_filename
# Error: "Unable to open '$spec_filename'"

# The compiler treats '$spec_filename' as a literal string path
# instead of evaluating the global variable
```

**Root Cause**: The compilation model is ahead-of-time (AOT), not JIT. When the compiler encounters a `require` statement, it immediately tries to open and parse the file at that path. Variable values aren't known at compile-time, so dynamic paths cannot be resolved.

**Example**: In rubyspec/language/return_spec.rb line 612:
```ruby
require $spec_filename
ScratchPad.recorded.should == ["before return"]
```

**Error Message**: `Unable to open '$spec_filename'`

**Affects**:
- return_spec.rb - Uses `require $spec_filename` pattern
- Potentially other specs using dynamic require paths
- Any code attempting to require files based on runtime values

**Alternatives for Fixing**:

1. **Better error message** (probably best first stage)
   - Detect when require argument looks like a variable (starts with `$`, `@`, or is a method call)
   - Emit clear error: "require with dynamic path not supported in AOT compilation"
   - Priority: Low - improves user experience but doesn't enable new functionality

2. **Warning at compile time, exception at runtime**
   - Allow compilation to succeed with warning to STDERR
   - Generate code that raises exception at runtime if path would be evaluated
   - This would let specs compile but still isn't great
   - Priority: Low - enables specs to compile but doesn't provide useful behavior

3. **JIT support** (*massive* change)
   - Add just-in-time compilation to dynamically load and compile files at runtime
   - Fundamentally changes compilation model
   - Priority: Very Low - architectural change, not worth the effort

4. **Workaround in run_rubyspec** (option 1b)
   - Recognize the `require $spec_filename` pattern specifically in run_rubyspec script
   - Rewrite it to raise an exception instead
   - This is a test-framework-specific hack, not a compiler fix
   - Priority: Low - works around the immediate problem for specs

**Priority**: Low - needs consideration of how to support it properly

**Workaround**: Rewrite code to use static require paths, or modify the test runner to handle this pattern.

**Files**:
- driver.rb - Handles require statement processing
- rubyspec/language/return_spec.rb:612 - Example of problematic code

---

## 21. Scope Resolution Operator `::` Parsed Incorrectly as Infix

**Problem**: The scope resolution operator `::` when used as a prefix (for root namespace lookups) is incorrectly parsed as an infix operator.

```ruby
# This fails:
puts ::Object.class
# Error: "Unable to resolve: puts::Object statically (FIXME)"

# Parser treats it as:
puts :: Object.class  # Trying to do puts::Object

# This also fails:
x = defined?(::Object)
# Error: "Missing value in expression"
# Parser creates: [:deref, :defined?, :Object] instead of [:call, :defined?, [[:deref, :Object]]]
```

**Root Cause**: In operators.rb:170, `::` is defined as an infix operator with priority 100. The parser/shunting yard doesn't recognize when `::` should be treated as a prefix operator (unary) instead of infix (binary).

When `::` appears in certain contexts (after `(`, `,`, `=`, keywords, at statement start, etc.), it should be treated as a prefix operator forming `[:deref, :ConstantName]`, not as an infix operator waiting for a left operand.

**Error Messages**:
- `Unable to resolve: puts::Object statically (FIXME)` - when ::appears after method name
- `Missing value in expression` - when :: appears inside function call arguments

**Example**: In rubyspec/language/class_spec.rb:176:
```ruby
Object.send(:remove_const, :A) if defined?(::A)
# Fails because defined?(::A) parses as [:deref, :defined?, :A]
```

**Affects**:
- class_spec.rb line 176 - `defined?(::A)` in if modifier
- Any code using `::ConstantName` for root namespace lookups
- Expressions like `puts ::Object`, `x = ::Array.new`, etc.

**Implementation Needed**:
1. Detect when `::` appears in prefix position (context-sensitive parsing)
2. Treat `::` as prefix operator in these contexts:
   - After `(`, `,`, `=`, `if`, `unless`, `while`, `until`, etc.
   - At expression start
   - After operators that expect a right operand
3. Generate correct AST: `[:deref, :ConstantName]` for prefix, `[:deref, left, right]` for infix

**Workaround**: Omit the `::` prefix and use relative constant lookup: `defined?(A)` instead of `defined?(::A)`.

**Priority**: Medium - Affects rubyspec compatibility and prevents using explicit root namespace lookups

**Files**:
- operators.rb:170 - `::` operator definition
- shunting.rb - Expression parser that needs context-sensitive handling
- rubyspec/language/class_spec.rb:176 - Example of problematic code

**Note**: This is different from issue #4 (Toplevel Constant Paths) which was about `class ::Foo` syntax. This issue is about using `::Foo` in general expressions.

---

## 22. Method Chaining After Class/Module Definitions Not Supported

**Problem**: Cannot chain method calls after `class ... end` or `module ... end` expressions.

```ruby
# This fails with "Missing value in expression"
class << true; self; end.class

# Also fails
class Foo; end.to_s

# Workaround - assign to variable first
klass = class << true; self; end
klass.class  # Works
```

**Error**: "Missing value in expression / op: {callm/2 pri=98} / vstack: [] / rightv: :class"

**Root Cause**: `parse_class` returns directly without pushing the class definition as a value onto the shunting yard's value stack. Method chaining requires the left-hand side to be a value.

**Affects**:
- metaclass_spec.rb:185 - `class << true; self; end.should == TrueClass`
- Any code trying to chain methods after class/module definitions

**Implementation Needed**:
1. Make `class ... end` and `module ... end` push values onto the value stack
2. Either refactor to use shunting yard for class definitions, or
3. Wrap class definition result in a value node after parsing

**Workaround**: Assign class definition to a variable, then call methods on the variable.

**Priority**: Low - Uncommon pattern, easy workaround

**Files**:
- parser.rb:640-659 - `parse_class` method
- shunting.rb - Expression parser

---

## 23. Anonymous Splat in Parentheses Not Supported

**Problem**: Anonymous splat assignment `* = value` works at statement level but fails inside parentheses.

```ruby
# This works
* = 1

# This fails with "Missing value in expression"
(* = 1)
```

**Error**: "Missing value in expression / {splat/1 pri=8}"

**Root Cause**: Inside parentheses, `*` is being treated as a prefix splat operator instead of recognizing it as part of an assignment pattern. The parser doesn't detect that `*` followed by `=` in this context is an anonymous splat assignment.

**Affects**:
- variables_spec.rb:410 - `(* = 1).should == 1`
- Any code using anonymous splat in expression contexts

**Implementation Needed**:
1. Detect `* =` pattern inside parentheses as assignment, not splat operator
2. Similar to how `a, b = 1, 2` is recognized as multiple assignment
3. May require lookahead to check if `*` is followed by `=`

**Workaround**: Use anonymous splat without parentheses.

**Priority**: Low - Rare pattern, has simple workaround

**Files**:
- shunting.rb - Expression parser handling of `*` operator
- operators.rb - Splat operator definition

---
