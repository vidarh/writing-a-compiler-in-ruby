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

## 25. Rescue in do...end Blocks - RESOLVED ✓

**Status**: ✅ RESOLVED (2025-11-15)

**Problem**: Exception handling with rescue clauses inside lambda/proc blocks didn't work. Exceptions propagated out instead of being caught.

```ruby
result = lambda do
  raise "error"
rescue
  42
end
result.call  # Now ✓ Returns 42
```

**Resolution**: Fixed in combination with issue #28

**Changes Made**:
1. **treeoutput.rb** (line 271): Preserve rescue/ensure clauses when converting :proc to :lambda
   - Changed from `E[:lambda, proc_node[1], proc_node[2]]`
   - Changed to `E[:lambda, proc_node[1], proc_node[2], proc_node[3], proc_node[4]]`

2. **transform.rb** (lines 50-51, 59-61): Wrap lambda body with rescue/ensure in :block nodes
   - Extract rescue_clause (e[3]) and ensure_clause (e[4])
   - Wrap body: `E[:block, E[], body, rescue_clause, ensure_clause]` when rescue/ensure present

3. **compiler.rb** (lines 709-759): Preserve eax across clear() and ensure (see issue #28)

**Test Results**:
- ✅ spec/do_block_rescue_spec.rb: 2/2 tests pass (was 0/2, FAIL status)
- ✅ selftest passes
- ✅ begin/rescue now returns rescue body values

**Affects**:
- spec/do_block_rescue_spec.rb - Now passing
- rubyspec/language/block_spec.rb:342 - Should now work
- All code using rescue clauses inside lambda/proc blocks

---

## 28. begin/rescue Returns nil Instead of Rescue Body Value - RESOLVED ✓

**Status**: ✅ RESOLVED (2025-11-15)

**Problem**: Rescue clauses executed but returned nil instead of the rescue body's value.

```ruby
result = begin
  raise "error"
rescue
  42
end
puts result  # Now ✓ Prints "42" (was nil)
```

**Resolution**: Preserve eax across clear() and ensure clause using stack push/pop

**Root Cause**: In compiler.rb compile_begin_rescue, the rescue body value in eax was overwritten by:
1. `[:callm, :$__exception_runtime, :clear]` call
2. ensure clause execution if present

**Changes Made** (compiler.rb):
1. **Lines 709-720** (normal completion path):
   - `pushl %eax` before ensure clause
   - `popl %eax` after ensure clause

2. **Lines 739-759** (rescue path):
   - `pushl %eax` before clear() call
   - `popl %eax` after clear()
   - `pushl %eax` again before ensure (if present)
   - `popl %eax` after ensure

**Test Results**:
- ✅ test_tiny_begin2.rb: Returns 42 (was nil)
- ✅ spec/do_block_rescue_spec.rb: 2/2 tests pass
- ✅ selftest passes with 0 failures

**Affects**:
- ALL begin/rescue blocks - now work correctly
- Unblocked issue #25 (rescue in lambdas)
- All code relying on rescue clause return values

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

**CRITICAL**: See issue #30 - for loops compile but fail at runtime with "undefined method" errors for loop variables

---

## 30. for Loops and Lambdas at Toplevel Don't Work

**Status**: LIMITATION - lambdas/procs/for loops only work inside methods

**Problem**: Lambdas, procs, and for loops fail at toplevel with "undefined method" errors for their parameters. They work correctly when defined inside methods.

```ruby
# At toplevel - FAILS:
for i in [1, 2, 3]
  puts i
end
# ✗ Unhandled exception: undefined method 'i' for Object

x = lambda { |i| puts i }
x.call(42)
# ✗ Unhandled exception: undefined method 'i' for Object

# Inside method - WORKS:
def test
  for i in [1, 2, 3]
    puts i
  end
end
test  # ✓ Prints 1, 2, 3
```

**Root Cause**: The `rewrite_lambda()` transformation is only called from `rewrite_let_env()`, which processes `:defm` (method definition) nodes. Toplevel code is not inside a `:defm`, so lambdas/procs at toplevel never get the transformation that sets up:
1. The `__env__` closure environment
2. The `__closure__` parent scope reference
3. Proper parameter binding in the generated `:defun`

Without this transformation, parameter references like `i` fall through to method_missing.

**Impact**:
- for loops only work inside methods
- Lambda/proc definitions only work inside methods
- This affects both user-written lambdas and compiler-generated procs (like from `for` loops)

**Affects**:
- rubyspec/language/for_spec.rb - many tests use toplevel for loops
- Any toplevel lambda/proc/for loop usage

**Workaround**: Define lambdas and for loops inside methods:
```ruby
def main
  for i in [1,2,3]; puts i; end
  x = lambda { |i| puts i }
  x.call(42)
end
main
```

**Technical Details**:
The `rewrite_lambda()` function transforms `:lambda` and `:proc` nodes into proper closures with environment setup:
```ruby
[:proc, [params], body]
=>
[:do,
  [:assign, [:index, :__env__, 0], [:stackframe]],
  [:assign, :__tmp_proc, [:defun, "lambda_123", [:self, :__closure__, :__env__] + params, body]],
  [:sexp, [:call, :__new_proc, [:__tmp_proc, :__env__, :self, arity, :__closure__]]]
]
```

This transformation assumes `__env__` and `__closure__` are available, which they are inside methods (via `rewrite_let_env`), but not at toplevel.

**Potential Fix**:
1. Wrap toplevel code in an implicit main method, OR
2. Create a toplevel-specific version of `rewrite_lambda` that doesn't require `__env__`/`__closure__`, OR
3. Initialize `__env__` and `__closure__` in the toplevel context before any lambda/proc usage

**Priority**: MEDIUM - Can be worked around by using methods

---

## 29. Long Method Names Cause Assembly Comment Header Crashes - RESOLVED ✓

**Status**: ✅ RESOLVED (2025-11-15)

**Problem**: Method names longer than ~70 characters caused compilation to fail with "negative argument (ArgumentError)" in emitter.rb:614.

```ruby
class Container
  def explicit_return_in_rescue_and_explicit_return_in_ensure
    # ... code ...
  end
end
# ✗ Compilation failed: emitter.rb:614:in `*': negative argument (ArgumentError)
```

**Root Cause**: The `func()` method in emitter.rb generates a centered comment header for each function:

```ruby
lspc = (70 - name.length) / 2
rspc = 70 - name.length - lspc
emit("#{"#"*lspc} #{name} #{"#"*rspc}")
```

When the method name (including class prefix like `__method_Container_explicit_return...`) exceeds 70 characters, `lspc` becomes negative, causing `"#"*lspc` to raise ArgumentError.

**Resolution**: Truncate long names in comments while preserving readable labels for short names

**Changes Made** (emitter.rb:611-623):
```ruby
# Truncate long names for the comment header to avoid negative lspc
# Keep names under 60 chars to leave room for padding
display_name = name.to_s
if display_name.length > 60
  # Truncate and add hash suffix for uniqueness
  hash_suffix = display_name.hash.abs.to_s(16)[0..7]
  display_name = display_name[0..50] + "..." + hash_suffix
end

lspc = (70 - display_name.length) / 2
rspc = 70 - display_name.length - lspc

emit("#{"#"*lspc} #{display_name} #{"#"*rspc}")
```

**Implementation Details**:
- Short names (≤60 chars): Used as-is in comment headers for readability
- Long names (>60 chars): Truncated to 50 chars + "..." + 8-char hash suffix
- Hash suffix ensures uniqueness when multiple long names truncate to same prefix
- Actual assembly label (used in stabs/export/label) remains full name - only comment is truncated

**Example Output**:
```assembly
#### __method_Container_explicit_return_in_rescue_and_ex...131635f2 ####

.stabs "__method_Container_explicit_return_in_rescue_and_explicit_return_in_ensure:F(0,0)",36,0,0,__method_Container_explicit_return_in_rescue_and_explicit_return_in_ensure
.globl __method_Container_explicit_return_in_rescue_and_explicit_return_in_ensure
```

**Test Results**:
- ✅ test_long_method_name.rb: Now compiles successfully
- ✅ rubyspec/language/ensure_spec.rb: Now compiles (was COMPILE FAIL)
- ✅ selftest: Passes with 0 failures
- ✅ selftest-c: Passes with 0 failures

**Affects**:
- rubyspec/language/ensure_spec.rb (now compiles, was blocked by this bug)
- Any spec files with methods having long descriptive names
- Particularly affects specs with ensure/rescue that use explicit method names

**Priority**: Medium - Fixes compilation failure for ensure_spec.rb and any code with long method names

---

## 31. Special Global Variables Not Assembly-Safe - RESOLVED ✓

**Status**: ✅ RESOLVED (2025-11-16)

**Problem**: Global variables with special characters like `$!`, `$@`, `$/`, etc. caused assembly errors because they were emitted as invalid assembly labels.

**Example**:
```ruby
puts $!.inspect   # Caused assembly error: invalid char '!' beginning operand
```

**Assembly Error**:
```
out/rubyspec_temp_throw_spec.s:144188: Error: invalid char '!' beginning operand 1 `!'
out/rubyspec_temp_throw_spec.s:154871: Error: junk at end of line, first unrecognized character is `!'
```

The BSS section would define `!:` as a label (after stripping `$`), and code would reference it as `movl !, %eax`, both invalid assembly.

**Root Cause**:
- Special global variables like `$!` were having the `$` prefix stripped to create assembly labels
- This left invalid characters like `!`, `@`, `/`, etc. in the assembly
- No mapping existed to convert these to assembly-safe names

**Resolution**: Added comprehensive alias mapping in globalscope.rb for all special globals:

```ruby
@aliases = {
  :"$:" => "LOAD_PATH",                 # Load path array
  :"$0" => "__D_0",                      # Program name
  :"$!" => "__exception_message",        # Last exception (set by raise)
  :"$@" => "__exception_backtrace",      # Last exception backtrace
  :"$?" => "__child_status",             # Status of last child process
  :"$/" => "__input_record_separator",   # Input record separator
  :"$\\" => "__output_record_separator", # Output record separator
  :"$," => "__output_field_separator",   # Output field separator
  :"$;" => "__field_separator",          # Default separator for split
  :"$." => "__input_line_number",        # Current input line number
  :"$&" => "__last_match",               # String matched by last regex
  :"$$" => "__process_id"                # Process ID
}
```

**Changes Made**:

1. **globalscope.rb:23-35** - Extended `@aliases` hash with all special globals
2. **globalscope.rb:56-73** - Modified `get_arg` to:
   - Return aliased names for special globals
   - Register aliases in `@globals` (not original symbols)
   - Strip `$` prefix from regular globals and register clean names
3. **lib/core/exception.rb:231-233** - Initialize `$!` to nil at startup to prevent segfaults

**Files Modified**:
- globalscope.rb - Alias mapping and clean name registration
- lib/core/exception.rb - Initialize `$!` to nil

**Test Results**:
- ✅ throw_spec.rb: Now compiles successfully (was assembly error)
- ✅ END_spec.rb: Now compiles successfully (was assembly error from $?)
- ✅ test_exception_global.rb: Compiles and runs, prints "nil"
- ✅ Assembly uses `__exception_message` label instead of `!`
- ✅ Assembly uses `__child_status` label instead of `?`
- ✅ selftest: Passes with 0 failures
- ✅ selftest-c: Passes with 0 failures

**Affects**:
- rubyspec/language/throw_spec.rb (now compiles, was blocked)
- Any code using special global variables
- Exception handling code using `$!`

**Priority**: High - Enables compilation of code using Ruby's standard special globals

---

## 32. Rest Parameters After Variable Renaming - RESOLVED ✓

**Status**: ✅ RESOLVED (2025-11-16)

**Problem**: In `transform.rb`, the code assumed rest parameters (`*args`) were always Symbols, causing crashes when they became indexed environment accesses after variable renaming.

**Error**:
```
transform.rb:526:in `block in rewrite_let_env': undefined method `to_sym' for [:index, :__env__, 10]:AST::Expr
```

**Root Cause**:
- `rewrite_lambda` processes lambdas/procs and can rename variables to `[:index, :__env__, N]` for closure access
- Later, `rewrite_let_env` processes rest parameters with `rest.to_sym`, assuming `rest` is a Symbol
- But after variable renaming, `rest` might be an AST expression like `[:index, :__env__, 10]`
- This caused a NoMethodError when trying to call `.to_sym` on an Array

**Resolution**: Modified transform.rb:525-540 to handle rest parameters that might be either Symbols or indexed expressions:

```ruby
if rest && rest != :__copysplat
  # rest might be a symbol or an indexed env access [:index, :__env__, N]
  # after variable renaming. Extract the symbol if needed.
  rest_sym = rest.is_a?(Symbol) ? rest : rest
  rest_target = rest  # Use original rest as assignment target

  vars << rest_sym if rest_sym.is_a?(Symbol)
  rest_func =
    [E[:sexp,
     [:assign, rest_target, [:__splat_to_Array, :__splat, [:sub, :numargs, ac]]]
    ]]
end
```

**Changes Made**:
- **transform.rb:525-540** - Check if rest is a Symbol before using, use rest directly as assignment target

**Test Results**:
- ✅ Fixed the `.to_sym` error in send_spec.rb compilation
- ✅ selftest: 0 failures
- ✅ selftest-c: 0 failures

Note: send_spec.rb still has other compilation issues (`:comma` in assignments), but this fix resolves the rest parameter crash.

**Priority**: Medium - Fixes a class of transform crashes with rest parameters in closures

---

## 33. Multi-Assignment with Method Calls on Left Side - NOT IMPLEMENTED

**Status**: ❌ NOT IMPLEMENTED

**Problem**: The compiler doesn't support multi-assignment (parallel assignment) when the left-hand side includes method calls, only when it's simple variables or destructuring.

**Example**:
```ruby
a, self.foo = 3, value   # Fails: method call on left side
a, b = 1, 2              # Works: simple variables
```

**Error**:
```
Expected an argument on left hand side of assignment - got subexpr,
(left: [:comma, :a, [:callm, :self, :foo]], right: [[:sexp, 3], :value])
```

**Root Cause**:
- The parser creates a `:comma` node for multi-assignment like `a, b = x, y`
- The compiler's `compile_assign` expects left-hand side to be either:
  - A simple symbol (`:a`)
  - A destructuring pattern (`[:destruct, :a, :b]`)
  - An index operation (`[:index, obj, key]`)
  - An instance variable (`@foo`)
- It doesn't handle `:comma` nodes which represent multiple targets including method calls
- This is a complex feature requiring:
  1. Evaluating the right-hand side values
  2. Storing them temporarily
  3. Assigning to each target (which might be variables OR method calls)
  4. Handling the different target types appropriately

**Workaround**: Use separate assignment statements:
```ruby
# Instead of:
a, self.foo = 3, value

# Use:
tmp = [3, value]
a = tmp[0]
self.foo = tmp[1]
```

**Affects**:
- send_spec.rb (compilation fails on this feature)
- Any code using parallel assignment with setter method calls

**Priority**: Low - Rare syntax, easy workaround

---

## 34. Method Parameters Transformed to Environment Accesses in Closures

**Status**: 🔴 UNRESOLVED - Complex issue requiring careful design

**Problem**: When a method definition contains lambda closures in default parameter values that capture other parameters, the transform phase incorrectly renames the parameter names themselves to `[:index, :__env__, N]` expressions instead of only renaming references within the closure.

**Error**:
```
/app/function.rb:12:in `initialize': Internal error: Arg.name must be Symbol; '[:index, :__env__, 4]'
```

**Example Code**:
```ruby
def foo(output = 'a', prc = -> n { output * n })
  prc.call(5)
end
```

**Root Cause**: The `rewrite_env_vars` function in transform.rb:352 handles `:lambda`, `:proc`, and `:defun` nodes specially to avoid rewriting parameter names. However, `:defm` (method definitions) are not in this list, so parameter names get renamed along with variable references when processing closures.

**Investigation Findings**:
1. Adding `:defm` to the special handling list (line 356) seems logical but causes regressions
2. The issue is that default parameter values use `#paramname` references that need special handling
3. The error "Expected lvar - #" indicates the parameter lookup mechanism breaks
4. This is a complex interaction between:
   - Variable renaming for closure capture (transform.rb)
   - Method parameter processing (function.rb)
   - Default parameter value handling (output_functions.rb)

**Attempted Fix**: Adding `:defm` alongside `:lambda`/`:proc`/`:defun` in `rewrite_env_vars` causes:
- Default parameter handling to break
- `get_lvar_arg` failures when looking up `#param` references
- Selftest failures with "Expected lvar - #" errors

**Affects**:
- def_spec.rb (compilation fails)
- Any method with lambda closures in default parameters that capture other parameters

**Workaround**: Don't use lambda closures in default parameters that capture other parameters. Use instance variables or separate the logic:
```ruby
# Instead of:
def foo(output = 'a', prc = -> n { output * n })

# Use:
def foo(output = 'a', prc = nil)
  prc ||= -> n { output * n }
end
```

**Priority**: Medium - Affects advanced Ruby features, but workaround exists

**Next Steps**: This requires deep analysis of the transform phase and how it interacts with method parameter handling. The fix likely requires:
1. Understanding why default parameters need `#param` references
2. How `:defm` differs from `:defun` in parameter handling
3. Whether `:defm` should have special handling or if the issue is elsewhere

---
