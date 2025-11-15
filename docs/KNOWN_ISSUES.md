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

## 6. Float Support Limited

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

## 13. Alias Keyword - PARTIALLY IMPLEMENTED

**Status**: 🟡 PARTIALLY IMPLEMENTED (2025-11-15)

**What Works**:
- ✅ Inside classes: `alias new_name old_name` works correctly
- ✅ Parser recognizes `alias` keyword
- ✅ Compiler generates correct vtable entries

**What Doesn't Work**:
- ❌ Top-level: `alias` at top-level doesn't create global method aliases

**Problem**: The `alias` keyword works inside classes but not at top-level.

```ruby
# This works:
class Foo
  def original_method
    42
  end
  alias new_method original_method  # ✓ Works
end
Foo.new.new_method  # => 42

# This doesn't work:
def foo
  "hello"
end
alias bar foo  # ✗ Compiles but bar is undefined
bar  # => "undefined method 'bar' for Object"
```

**Root Cause**: The `compile_alias` method (compile_class.rb:47-59) only handles class-scoped aliases. It requires a `class_scope` and updates the class vtable. Top-level methods are in Object's vtable but the top-level context doesn't have proper class_scope handling for alias.

**Impact**:
- alias_spec.rb fails at runtime (compiles successfully)
- Top-level aliases not supported
- Class-level aliases work fine

**Workaround**:
```ruby
# At top-level, define method that calls original:
def bar
  foo
end

# Or use class scope:
class Object
  alias bar foo
end
```

**Test**: Class aliases work; top-level aliases compile but fail at runtime

**Priority**: Low - Class aliases work (common case), top-level has workaround

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

## 22. Method Chaining After Singleton Class Definitions Not Supported

**Status**: 🟡 PARTIALLY FIXED (2025-11-15)

**What Works**:
- ✅ Regular class definitions: `class Foo; end.class` returns `Class`
- ✅ Module definitions: `module Bar; end.class` returns `Module`

**What Doesn't Work**:
- ❌ Singleton class in statement position: `class << obj; self; end.class` fails with parse error
- ✅ **Workaround works**: `result = (class << obj; self; end).class` - using assignment or parentheses

**Problem**: Cannot chain method calls after singleton class (`class << obj`) expressions.

```ruby
# This fails in statement position:
class << true; self; end.class  # ✗ Parse error

# These work:
class Foo; end.class              # ✓ Returns Class
module Bar; end.class             # ✓ Returns Module
result = (class << true; self; end).class  # ✓ Returns Class (with assignment)

# Workarounds:
klass = class << true; self; end
klass.class  # ✓ Works

(class << true; self; end).class  # ✓ Works with parentheses
```

**Error**: "Missing value in expression / op: {callm/2 pri=98} / vstack: [] / rightv: :class"

**Root Cause**: Regular `class` and `module` now work (likely fixed when class became an expression). Singleton class (`class <<`) still has the old behavior where it doesn't push a value onto the value stack.

**Affects**:
- metaclass_spec.rb:185 - `class << true; self; end.should == TrueClass`
- Any code trying to chain methods after singleton class definitions

**Implementation Needed**:
1. Make `class << obj ... end` push value onto the value stack (like regular class now does)
2. Update singleton class parser to match regular class behavior

**Workaround**: Assign singleton class to a variable, then call methods on the variable.

**Priority**: Low - Uncommon pattern, easy workaround, regular class/module already work

**Files**:
- parser.rb - Singleton class parser
- shunting.rb - Expression parser

---

## 23. Anonymous Splat Assignment Not Supported

**Problem**: Anonymous splat assignment `* = value` is not supported at all (neither at statement level nor in parentheses).

```ruby
# This fails with "Missing value in expression"
* = 1

# This also fails
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

## 24. Method Chaining Across Newlines - RESOLVED ✓

**Status**: ✅ RESOLVED (2025-11-15)

**Problem**: Cannot chain method calls when the `.` operator starts a new line.

```ruby
# This used to fail:
foo()
  .to_s  # Error: "Missing value in expression"

# Now works! ✓
foo()
  .to_s

# Also works:
[1, 2, 3]
  .reverse
  .first
```

**Resolution**: Implemented lookahead in scanner's nolfws() method

**Changes Made**:
1. **scanner.rb**: Modified `nolfws()` to check if newline is followed by `.`
2. **scanner.rb**: Added `peek_past_newline_is_dot?()` helper method
3. When `nolfws()` encounters a newline, it peeks ahead past horizontal whitespace
4. If next character is `.`, treats newline as whitespace and continues
5. If not `.`, stops at newline as before (preserves statement boundary behavior)

**Implementation Details**:
```ruby
def nolfws
  while (c = peek) && NOLFWS.member?(c.ord) do get; end
  # Check if newline is followed by . (method chaining)
  if peek == LF && peek_past_newline_is_dot?
    get  # consume the newline
    nolfws  # recursively skip more whitespace
  end
end

def peek_past_newline_is_dot?
  # Save state, consume newline + spaces, check for ., restore state
  # Returns true if next line starts with .
end
```

**Test Results**:
- ✅ selftest passes
- ✅ selftest-c passes
- ✅ spec/method_chain_newline_spec.rb: 3/3 tests pass

**Note**: Only modified `nolfws()`, not `ws()`, to avoid interfering with comment handling

---

## 25. Rescue in do...end Blocks - PARTIALLY FIXED

**Problem**: Exception handling with rescue clauses inside lambda/proc blocks doesn't work. Exceptions propagate out instead of being caught.

```ruby
# This fails:
result = lambda do
  raise "error"
rescue
  42
end
result.call  # ✗ Crashes with "Unhandled exception: error"
```

**Status**: 🟡 PARTIALLY FIXED (2025-11-15) - Blocked by issue #28

**Progress Made**:
1. ✅ Fixed treeoutput.rb (line 271) to preserve rescue/ensure clauses when converting :proc to :lambda
2. ✅ Fixed transform.rb (lines 50-51, 59-61) to wrap lambda body with rescue/ensure in :block nodes
3. ✅ selftest passes with these changes
4. ❌ Blocked by newly discovered bug: begin/rescue doesn't return rescue body values (see issue #28)

**Blocking Issue**: Rescue clauses now flow through to compiler but begin/rescue returns nil instead of rescue body value. This affects ALL rescue usage, not just lambdas.

**Affects**:
- spec/do_block_rescue_spec.rb - Minimal test case
- rubyspec/language/block_spec.rb:342 - "supports rescue inside do...end block"
- Any code using rescue clauses inside lambda/proc blocks

**Workaround**: Use begin/rescue/end instead of inline rescue in blocks:
```ruby
result = lambda do
  begin
    raise "error"
  rescue
    42
  end
end
result.call  # ✓ Works (but returns nil due to issue #28)
```

**Priority**: Medium - Partial progress made, full fix requires resolving issue #28

---

## 28. begin/rescue Returns nil Instead of Rescue Body Value

**Problem**: Rescue clauses execute but return nil instead of the rescue body's value.

```ruby
result = begin
  raise "error"
rescue
  42
end
puts result  # ✗ Prints "nil", should print "42"
```

**Status**: ❌ BUG - Discovered 2025-11-15

**Root Cause**: In compiler.rb compile_begin_rescue (lines 738-743), the rescue body is compiled but its value in eax is overwritten by:
1. `[:callm, :$__exception_runtime, :clear]` call (line 742)
2. ensure clause execution if present (line 745)

The method returns `Value.new([:subexpr])` expecting eax to hold the result, but eax was overwritten.

**Affects**:
- ALL begin/rescue blocks
- Blocks issue #25 (rescue in lambdas)
- Any code relying on rescue clause return values

**Workaround**: Assign rescue value to variable before end of rescue block:
```ruby
result = nil
begin
  raise "error"
rescue
  result = 42
end
puts result  # ✓ Prints "42"
```

**Fix Required**: In compile_begin_rescue, preserve eax value across clear() and ensure clause:
1. After rescue body (line 739): Save eax to local variable __result
2. After clear() and ensure (lines 742-745): Restore __result to eax
3. Same for normal completion path (lines 702-711)

**Priority**: HIGH - Affects all rescue usage, blocks other fixes

---

## 26. Hash Spread Operator (**) Not Supported

**Problem**: The hash spread operator `**` (also called kwsplat) is parsed as exponentiation operator instead of hash spread, causing parse errors.

```ruby
# This fails:
h = {b: 2, c: 3}
{**h, a: 1}  # ✗ Parse error: "Missing value in expression / op: {**/2 pri=21}"

# Expected behavior (MRI Ruby):
{**h, a: 1}  # => {:b=>2, :c=>3, :a=>1}
```

**Status**: Parser bug - `**` needs context-sensitive handling

**Root Cause**: The `**` operator is defined in operators.rb as an infix exponentiation operator (priority 21). Inside hash literals, `**expr` should be treated as a PREFIX hash spread operator, not as infix exponentiation.

**Current Parse Tree** (WRONG):
```ruby
result = {**h, a: 1}
# Parses as: [:hash, [:**, :result, :h], [:pair, :a, 1]]
# The ** operator consumed :result from OUTSIDE the hash as left operand!
```

**Expected Parse Tree** (CORRECT):
```ruby
result = {**h, a: 1}
# Should parse as: [:assign, :result, [:hash, [:kwsplat, :h], [:pair, :a, 1]]]
# The ** should be prefix operator creating [:kwsplat, :h] node
```

**Technical Details**:
1. `**` appears inside hash literal `{...}`
2. Parser calls `shunt_subexpr([HASH],src)` to parse hash contents (shunting.rb:161)
3. `shunt_subexpr` creates new operator stack but SHARES the value stack with outer expression
4. The `**` operator (infix) grabs values from outer expression's value stack
5. This causes `**` to consume `:result` variable from outside the hash

**Affects**:
- rubyspec/language/hash_spec.rb:163 - Hash spread expansion
- rubyspec/language/keyword_arguments_spec.rb - Keyword argument splatting
- Any code using `{**hash}` syntax for hash spreading

**Workaround**: Manually merge hashes instead of using spread operator:
```ruby
# Instead of: {**h1, **h2, a: 1}
# Use:
result = h1.dup
h2.each { |k, v| result[k] = v }
result[:a] = 1
```

**Implementation Needed**:
1. **Context-sensitive parsing**: Detect when `**` appears in hash literal context
2. **Treat as prefix operator**: Inside `{...}`, `**expr` should parse as `[:kwsplat, expr]`
3. **Isolate value stack**: Hash literals may need their own value stack context to prevent operators from reaching outside
4. **Compiler support**: Implement `compile_kwsplat` to handle hash spreading at runtime

**Alternative Approaches**:
- Add `**` as both infix (exponentiation) and prefix (kwsplat) operator with context detection
- Create separate `:kwsplat` operator that's only valid in hash contexts
- Modify `shunt_subexpr` to create isolated value stack for hash literals

**Test Files**:
- test_hash_spread.rb - Minimal reproduction
- spec/hash_spread_spec.rb - Comprehensive test cases

**Priority**: High - Blocks hash_spec.rb and keyword_arguments_spec.rb, common Ruby pattern

---

## 27. Method Chaining on for...end Loops - RESOLVED ✓

**Status**: ✅ RESOLVED (2025-11-15)

**Problem**: Cannot chain methods after `for...end` loops. The `for` keyword is parsed as a statement, not as an expression that returns a value.

```ruby
# This used to fail:
for i in 1..3; end.class
# Error: "Missing value in expression / op: {callm/2 pri=98} / vstack: [] / rightv: :class"

# Now works (matches MRI Ruby):
for i in 1..3; end.class  # => Range ✓
(for i in [:a, :b]; end).length  # => 2 ✓
```

**Resolution**: Implemented operator-based parsing for `for` loops (similar to while/until)

**Changes Made**:
1. **operators.rb**: Added `for` as `:for_stmt` operator with precedence 2
2. **parser.rb**: Created `parse_for_body()` method that doesn't consume 'for' keyword
3. **shunting.rb**: Added handler for `:for_stmt` in `oper()` method
4. **parser.rb**: Removed `parse_for` from `parse_defexp` chain
5. **transform.rb**: Modified `rewrite_for()` to return enumerable instead of nil
   - Transforms `for x in arr; body; end` to `(tmp = arr; tmp.each { |x| body }; tmp)`
   - This matches MRI Ruby semantics where for loops return the enumerable

**Implementation Details**:
```ruby
# operators.rb:
"for" => Oper.new(2, :for_stmt, :infix, 2, 2, :right, 1),

# shunting.rb:
elsif op.sym == :for_stmt
  @out.value(@parser.parse_for_body())
  return :prefix

# transform.rb (rewrite_for):
# for x in array; body; end => (tmp = array; tmp.each { |x| body }; tmp)
e[0] = :let
e[1] = [:__for_tmp]
e[2] = [:do,
  [:assign, :__for_tmp, enumerable],
  [:callm, :__for_tmp, :each, [], proc_node],
  :__for_tmp
]
```

**Test Results**:
- ✅ selftest-c passes (self-compilation verified)
- ✅ spec/for_end_method_chain_spec.rb: 2/3 tests pass (1 fails due to unrelated Range#== bug)
- ✅ Method chaining works: `(for i in 1..3; end).class` => Range

**Note**: One test fails because Range#== returns the Range object instead of a boolean true/false. This is a separate bug in lib/core/range.rb, not related to this fix

---
