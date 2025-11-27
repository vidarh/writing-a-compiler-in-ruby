# Known Issues

**Last Updated**: 2025-11-27 (Post Regexp Implementation)

## Current State Summary

**Test Status**: 78 language specs, 217/900 tests passing (24% pass rate)
- ✅ PASSED: 3 specs (and_spec, not_spec, unless_spec)
- ❌ FAILED: 23 specs - run but fail assertions
- 💥 CRASHED: 52 specs - segfaults/hangs
- 🎉 **COMPILE FAIL: 0 specs** - All specs now compile!

**Recent fixes** (Phase 1.1-1.3, Regexp):
- ✅ break returns nil (was returning false) - +3 tests
- ✅ String interpolation #{} in percent strings - eliminated all "hey #xxx" failures
- ✅ Post-test loops (begin...end until) execute body at least once
- ✅ Regexp support: matching, captures, case-insensitive, word boundaries
- ✅ String#gsub, String#split, String#scan with regexp support
- ✅ POSIX character classes in regexp (10 classes: alpha, digit, space, etc.)

**Expected limitations** (~500+ test failures):
- Regexp partially implemented: Many tests still fail (advanced features)
- eval() not supported (AOT): ~100 failures
- Float not implemented: ~17 failures
- Command execution: ~8 failures

**Fixable issues** (~152 test failures, 15% of all failures):
- Segfaults: ~300-450 tests blocked (Phase 3/4 work)
- Keyword arguments: ~60 tests (blocked on compiler changes)
- Missing methods: ~50 tests
- Hash edge cases: ~15 tests
- Other bugs: ~20+ tests

## Critical Issues Blocking Most Tests

### 1. Segmentation Faults (HIGHEST PRIORITY)

**Impact**: Blocks 50 spec files (64%), prevents ~450+ tests from running

**Symptoms**: Specs compile successfully but crash during execution, often after warnings like:
```
WARNING:    Method: 'attr'
WARNING:    symbol address = 0x57cdbff0
WARNING:    class 'Class'
```

**Affected areas**:
- Block/lambda/proc execution
- Method dispatch for attr/private/create_lambda
- Possible infinite loops or stack corruption

**Investigation needed**:
1. Use gdb/valgrind on simple failing spec (lambda_spec, loop_spec)
2. Check method lookup/dispatch for special methods
3. Review block/lambda/proc memory management
4. Look for stack overflow in recursive calls

**Files affected** (35+ specs): alias, array, break, case, class, hash, if, lambda, loop, proc, return, string, while, yield, and many more

---

### 2. Keyword Arguments / Hash Splatting

**Impact**: 60+ test failures

**Status**: Requires compiler changes (1-2 weeks estimated)

**Issue**: `:pair` and `:hash_splat` AST nodes aren't in compiler keywords list. When they appear as method arguments, they're treated as method calls instead of being properly compiled.

**Error**: "undefined method 'hash_splat' for #<Object>"

**Required work**:
1. Add `:pair` and `:hash_splat` to compiler keywords list
2. Implement `compile_pair` and `compile_hash_splat` methods
3. OR: Transform keyword args in transform.rb before compilation
4. Update argument passing conventions

**Files affected**: keyword_arguments_spec (0/26 tests pass), hash_spec, def_spec, END_spec

**Priority**: HIGH impact but BLOCKED on architectural changes - See docs/TODO.md Phase 1.4

---

### 3. Compound Expression After If/Else Corrupts Variables

**Impact**: "Integer can't be coerced" runtime errors in compiled code

**Symptoms**: Code like this crashes at runtime:
```ruby
if condition
  # branch A
else
  # branch B
end
result = obj.method1 + obj.method2  # CRASH HERE
```

**Root cause**: Compiler bug with register allocation or expression evaluation
after if/else blocks. The variable `obj` gets corrupted when evaluating compound
expressions immediately after the if/else.

**Workaround**: Break compound expressions into separate statements:
```ruby
if condition
  # branch A
else
  # branch B
end
# @bug: Compiler bug - compound expression after if/else corrupts variable
val1 = obj.method1
val2 = obj.method2
result = val1 + val2  # WORKS
```

**Affected code**: lib/core/string.rb (String#scan uses this workaround)

**Status**: Not fixed - workaround in place. Root cause needs investigation
in compile_control.rb or register allocation.

---

### 4. ✅ FIXED - String Interpolation in Percent Strings

**Status**: ✅ Fixed in commit a39b3ef

**Issue**: Interpolation with #{} in percent strings included extra "#":
```ruby
%(hey #{@ip})  # Was: "hey #xxx", Now: "hey xxx" ✓
```

**Root cause**: tokens.rb was adding "#" to buffer BEFORE checking for interpolation

**Fix**: Check for interpolation first, only add "#" if not followed by "{"

---

### 5. 11-Elsif Branch Crash in selftest-c

**Impact**: Prevents adding more than ~10 elsif branches in a single method in
lib/core/regexp.rb. Discovered when implementing POSIX character classes.

**Symptoms**: selftest-c crashes with segfault in `Class.allocate` when compiling
test/selftest.rb with the self-compiled compiler. GDB backtrace shows:
```
#0  __method_Class_allocate__1 () - movl %eax, (%edi) where edi=4 (invalid ptr)
#1  __method_Class_new ()
#2  __get_string ()
#3  __method_Integer_chr ()
#4  Emitter_string ()
#5  Compiler_output_constants ()
#6  Compiler_compile ()
#7  main ()
```

**Key observations**:
- Standalone test files with 11 elsif branches compile and run correctly
- Self-compiled driver (with 11 branches) works for simple files
- Crash ONLY occurs when self-compiled driver compiles test/selftest.rb
- Crash is in Class.allocate: `edi` register contains 4 (tagged fixnum for 2)
  instead of a valid array pointer from `__array` call
- The crash happens during string constant output in Emitter#string

**Root cause**: Unknown. The bug is in the self-compiled binary, not the source.
Adding an 11th elsif branch to `__posix?` in regexp.rb causes the resulting
self-compiled binary to crash when processing large files with many string
constants. Likely a code generation bug that causes stack or register corruption.

**Workaround**: Split long elsif chains into multiple methods. For POSIX classes,
`__posix?` was split into `__posix_low?` (4 branches) and `__posix_high?` (6 branches).

**Reproduction**: Run `./spec/reproduce_11branch_crash.sh` to automatically reproduce the crash.

**Current POSIX support**: 11 classes implemented (alpha, alnum, blank, cntrl,
digit, graph, lower, space, upper, word, xdigit). Punct NOT implemented due to
this bug - would require a 12th branch or third split method.

**Status**: Workaround in place. Root cause needs investigation.

---

## Quick Wins (Remaining Easy Implementations)

### Missing Core Methods (~40 test impact, ~6 hours work)

1. **`Kernel#catch`/`throw`** - 18 tests (throw_spec crashes, needs proper non-local return)
2. **`String#=~`, `Regexp#=~`** - 10 tests (can stub to return nil)
3. **`Object#instance_eval`** - Variable impact (many specs need this)
4. **`Object#proc`** - ~5 tests (Proc creation helper)
5. **`Kernel#fixture`** - ~10 tests (Test framework helper, already stubbed)

### ✅ Completed Quick Wins

1. ✅ **Fix `break` return value** - Fixed in Phase 1.1 (+3 tests)
2. ✅ **`Object#redo`** - Stubbed to raise RuntimeError (+0 tests, prevents crashes)
3. ✅ **`begin...end until` loop** - Fixed in Phase 1.3 (+3 tests estimated)

**Files affected**: until_spec (remaining ~5 failures)

---

## Medium Priority Issues

### Hash Edge Cases (15+ test impact)

1. `{=> value}` should create `{nil => value}`, creates `{}`
2. `**nil` in hash literal should expand to `{}` or raise TypeError
3. Missing `Hash#to_hash` for splatting

### BEGIN/END Blocks (14+ test impact)

- BEGIN blocks: BEGIN_spec crashes immediately
- END blocks: END_spec has 14 failures

### Missing Utility Methods (20+ test impact)

1. `Kernel#fixture` - Test framework helper (~10 tests)
2. `Object#singleton_class` - Reflection (~2 tests)
3. `Object#instance_eval` - Dynamic evaluation (variable impact)
4. `Object#proc` - Proc creation (~5 tests)

---

## Known Limitations (Cannot Fix - 632 test failures)

These are fundamental architectural constraints:

1. **Regular Expressions Not Implemented** (507 failures)
   - All regexp/* specs fail
   - match_spec fails (uses `=~` operator)
   - Cannot implement without major work

2. **eval() Not Supported** (~100 failures)
   - AOT (ahead-of-time) compilation model
   - Cannot evaluate strings as code at runtime
   - Many specs use `eval()` to test syntax errors

3. **Float Type Not Implemented** (~17 failures)
   - numbers_spec: Float, Rational, Complex literals fail
   - Exponent notation (`1e5`) not supported

4. **Command Execution Not Supported** (~8 failures)
   - Backticks: `` `command` ``
   - `%x{command}` syntax
   - execution_spec: All command execution tests fail

**Maximum achievable pass rate**: ~80-85% (800-850 tests) even with all bugs fixed

---

## Recent Fixes (2025-11-26)

✅ **Pattern Matching** - Now compiles successfully!
- Fixed closure variable capture bug (transform.rb:704)
- All language specs now compile (0 COMPILE FAIL)
- Known limitation: pattern-bound variables don't work in nested closures
- See issue #XX below for details

## ✅ FIXED: Parser Bug: `obj.method []` Incorrectly Parsed as Indexing

**Status**: Fixed in commit [pending]

**Problem**: `obj.method []` was parsed as `(obj.method)[]` instead of `obj.method([])`

**Solution**:
- Added whitespace tracking to Scanner (`@had_ws_before_token`)
- Modified `ws()` and `nolfws()` to track whitespace consumption
- Updated shunting.rb to check whitespace before `[` and treat it as argument when after method call

**Files Modified**:
- scanner.rb: Added `@had_ws_before_token` tracking
- tokenizeradapter.rb: Exposed whitespace flag
- shunting.rb: Check whitespace + method call context to decide if `[` is argument or indexing

---

## Detailed Issue Documentation

The sections below contain detailed documentation of individual bugs, organized by category.

---

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

## 2. Compiler Can't Handle Non-Constant Superclasses - PARTIALLY FIXED

**Status**: Parser now accepts expressions as superclasses (✓), but compiler crashes on non-constant superclasses.

**Problem**: The compiler assumes superclass is always a constant (symbol) and looks it up in @classes hash at compile time. When superclass is an expression (like `""`, `get_class()`, etc.), the compiler fails.

**Impact**:
- rubyspec/language/class_spec.rb: COMPILE FAIL (line 450 and others with non-constant superclasses)
- spec/class_superclass_atom_spec.rb: Compiles but doesn't raise TypeError at runtime

```ruby
# Parser now accepts these (✓), but compiler fails:
class TestClass < ""; end           # Compiler error: can't look up "" in @classes
class TestClass < get_class(); end  # Compiler error: can't look up expression
class TestClass < 1; end            # Compiler error: can't look up 1
```

**Root Cause**:
1. ✓ Parser fixed (parser.rb:738, 761) - now calls `parse_subexp` instead of `expect(Atom)`
2. ✗ Compiler (compile_class.rb:187) - `superc = @classes[superclass]` assumes superclass is a symbol
3. ✗ Missing runtime type check - should emit code to validate superclass is a Class and raise TypeError if not

**Implementation Needed**:
1. In compile_class.rb:187, detect if superclass is an expression (not a symbol)
2. If expression: emit runtime code to evaluate it, check it's a Class, use it as superclass
3. If symbol: use existing compile-time lookup in @classes hash
4. Add runtime check: `raise TypeError, "superclass must be a Class" unless superclass.is_a?(Class)`

**Priority**: HIGH - Causes COMPILE FAIL, blocks class_spec.rb

**Files**:
- parser.rb:738, 761 - FIXED: Now accepts expressions
- compile_class.rb:186-187 - Needs fix for runtime superclass evaluation
- Runtime needs TypeError check for invalid superclass types

**Location**: parser.rb:737 (parse_class) and parser.rb:746 (parse_class_body)

---

## 3. Parenthesized Control Flow - PARTIALLY RESOLVED

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

Also fails when followed by newline and new statement:
```ruby
a = (
  break if true
  c = false        # ✗ Parsed as: break if true(c) = false
)
```

**Error**: "Missing value in expression / op: {assign/2 pri=7} / vstack: [] / rightv: [:break, :result]" or "Expected an argument on left hand side of assignment - got subexpr"

**Root Cause**: When `break` (prefix operator, pri=22) is followed by `if` (infix operator, pri=2), the shunting yard algorithm doesn't correctly handle statement termination (newlines). The `if` modifier continues to consume tokens from the next statement.

**Test**: spec/break_if_modifier_spec.rb, spec/or_assign_paren_expr_spec.rb (compiles, runtime segfault)

**Affects**: while_spec.rb (COMPILE FAIL), until_spec.rb (test cases with `break if` patterns)

**Priority**: MEDIUM - workaround exists (use explicit if/end instead of modifier if)

---

## 3. Top-Level Blocks/Lambdas - FIXED

**Status**: ✅ FIXED (2025-11-26)

**Problem**: Blocks and lambdas at top-level were failing with "undefined method 'lambda'" or "undefined reference to '__env__'".

```ruby
lambda { 42 }               # ✓ Now works at top-level
[1,2,3].each { |i| puts i } # ✓ Now works at top-level
```

**Fix**: Modified `rewrite_let_env()` in transform.rb to also handle top-level procs:
1. After processing all `:defm` nodes, call `rewrite_lambda(exp)` on the entire expression
2. If top-level procs are found, wrap the top-level code in a `:let` that declares `__closure__`, `__tmp_proc`, and `__env__`
3. Initialize `__closure__` to 0 (no enclosing closure at top level) and allocate `__env__`

**Previous Root Cause**: The `rewrite_lambda()` function was only called from within `rewrite_let_env()`'s `:defm` processing loop. Top-level code is not inside a `:defm`, so top-level procs were never transformed.

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

## 17. Splat in Assignment LHS - RESOLVED (2025-11-16)

**Status**: ✅ FIXED

**Problem**: Destructuring assignments with splat on the left-hand side were not implemented.

**Error** (before fix):
```
Expected an argument on left hand side of assignment - got subexpr,
(left: [:splat, :c], right: [:callm, :__destruct, :[], [[:sexp, 5]]])
```

**Solution**: Enhanced `rewrite_destruct()` in transform.rb to handle [:splat, var] nodes:
- Variables before splat: assigned from positive indices (0, 1, ...)
- Variables after splat: assigned from negative indices (-1, -2, ...)
- Splat variable: collects remaining elements using Array#[start, length] or Array#[range]

**Examples** (now working):
```ruby
a, b, *c = [1, 2, 3, 4, 5]  # a=1, b=2, c=[3,4,5]
*a, b = [1, 2, 3]            # a=[1,2], b=3
a, *b, c = [1, 2, 3, 4]      # a=1, b=[2,3], c=4
```

**Implementation Details**:
For `a, *b, c, d = array`:
- a = array[0]
- c = array[-2]
- d = array[-1]
- b = array[1, [0, array.length - 1 - 2].max]  # handles edge cases

**Test Results**:
- selftest: PASS
- selftest-c: PASS
- next_spec.rb: Now COMPILES (was COMPILE FAIL)

**Files Changed**: transform.rb:711-795

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

**Status**: ✅ FIXED (2025-11-17, commit e0b645a)

**Problem**: When an if-statement has no else-branch and the condition is false, the expression returns the condition value instead of nil.

```ruby
result = if false then 123 end
puts result.inspect  # Was: false (WRONG) - Now: nil (correct)

result = if true then 123 end
puts result.inspect  # Outputs: 123 (correct)
```

**Root Cause**: In `compile_control.rb`, the `compile_if` function only generated the endif label and jump when `else_arm` was present. When there was no else-arm, the %eax register contained the condition value (false) instead of nil.

**Solution**: Modified `parser.rb` to automatically add `[:do, :nil]` as the else-branch for all if/unless statements without explicit else clauses. This parser-level fix is superior to compiler-level fixes because:
1. S-expression `%s(if ...)` code remains unaffected (critical for bootstrap)
2. No risk of breaking bootstrap code that depends on current behavior
3. All regular Ruby if-statements automatically get correct nil behavior
4. Cleaner AST structure - all if-statements consistently have both branches

**Changes**:
- `parser.rb:196-200`: Add explicit `[:do, :nil]` else-branch in `parse_if`
- `lib/core/symbol.rb:41-46`: Add explicit `else nil` to Symbol#<=> for code clarity
- `test/selftest.rb:670`: Update test expectation for new AST structure

**Impact**:
- ✅ selftest passes (0 failures)
- ✅ selftest-c passes (0 failures)
- ✅ if-without-else now correctly returns nil
- ✅ No regressions in bootstrap or existing tests

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

**Root Cause**: The splat operator `*` is defined as a prefix operator with arity=1, minarity=1 in operators.rb. This means it REQUIRES an operand. When `*` appears alone (as in `* = 1`), the parser treats it as a prefix operator expecting an operand, and throws "Missing value in expression" when it encounters `=` instead.

**Attempted Fixes**:
1. **Setting minarity=0** - Allows splat without operand, but causes "Expression did not reduce to single value" errors in normal splat usage like `foo(*bar)` because the operator reduces too early (before consuming its operand)
2. **Lookahead in shunting.rb** - Would require peeking ahead to see if `=` follows `*`, but proper implementation needs peek_token() method in scanner (using instance_variable_get/set violates CLAUDE.md rules)

**Affects**:
- variables_spec.rb:410 - `(* = 1).should == 1`
- Any code using anonymous splat in expression contexts

**Implementation Needed**:
1. Add proper peek_token() method to scanner.rb for lookahead without consuming
2. In shunting.rb, when encountering `*` in prefix position, peek ahead
3. If next token is `=`, push placeholder value (`:*`) instead of splat operator
4. compiler.rb already has handler for `left == :*` that treats it as no-op assignment

**Workaround**: Use explicit variable with multiple assignment: `_, = 1`

**Priority**: Low - Rare pattern, has workaround

**Files**:
- operators.rb - Splat operator definition (line 170)
- shunting.rb - Expression parser (needs lookahead for `* =` pattern)
- scanner.rb - Needs peek_token() method
- compiler.rb:729 - Already has anonymous splat handler (returns value without storing)

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

## 35. Regex Literal Tokenization Not Implemented (RESOLVED 2025-11-16)

**Problem**: The tokenizer did not recognize regex literals (`/pattern/`), causing them to be parsed as division operations instead.

**Example**:
```ruby
# This used to fail to parse:
x = (raise if 2+2 == 3; /a/)

# Was parsing as division: [:/, [:+, 2, 2], [:/, 3, :a]]
# Now correctly parses as regex
```

**Fix**: Added context-sensitive regex vs division detection in tokens.rb:475-515
- **Division context**: After identifiers (not keywords), number literals, or closing delimiters `)`, `]`, `}`
- **Regex context**: Everywhere else (after operators, keywords, semicolons, whitespace, etc.)
- Added newline termination for unterminated regex patterns
- Handles regex modifiers (i, m, x, o)

**Impact**:
- Reduced language spec compile failures from 47 to 41 (6 specs now compile)
- spec/regex_tokenization_spec.rb passes 4/4 tests
- selftest and selftest-c both pass with 0 failures

**Implementation**:
```ruby
# tokens.rb:475-515
when ?/
  keywords = [:if, :unless, :while, :until, :raise, :return, ...]
  is_division = @last && !@first && (
    (@last[1].nil? && @last[0].is_a?(Symbol) && !keywords.include?(@last[0])) ||
    (@last[1].nil? && @last[0].is_a?(Integer)) ||
    (@last[1].is_a?(Oper) && (@last[0] == ")" || @last[0] == "]" || @last[0] == "}"))
  )
```

**Note**: Full regex runtime implementation is not yet done - regexes compile but fail at runtime with "Regexp not implemented" (which is acceptable for now).

---

## 37. %Q{} Percent Literal Lookahead - REVERTED (2025-11-17)

**Problem**: Attempted to implement lookahead to distinguish `%Q{foo}` percent literals from modulo operator `%` by peeking ahead after consuming `%`. This approach was fundamentally broken and broke selftest-c.

**Attempted Implementation** (REVERTED):
```ruby
# Broken code (removed from tokens.rb):
if !is_percent_literal
  pct = @s.get      # Consume %
  if pct
    next_char = @s.peek
    if next_char && ALPHA.member?(next_char)
      is_percent_literal = true
    end
    @s.unget(pct)   # Put % back
  end
end
```

**Why It Failed**: The code logic itself was flawed (not a compilation issue). When compiled with the broken lookahead, the resulting compiler binary was corrupted and produced "undefined method 'nil' for Tokens__Tokenizer" errors at runtime.

**Current Implementation**: Simple heuristic using `@first || prev_lastop` to detect percent literals. This works for most cases but doesn't handle patterns like `eval %Q{foo}` where percent literal follows an identifier.

**Impact**:
- selftest-c: PASSES (with reverted code)
- Most percent literals work correctly
- Edge case `method_name %Q{string}` may not parse correctly

**Status**: Proper lookahead implementation deferred - current simple heuristic is sufficient for bootstrap

**Priority**: Low - Current heuristic works for compiler's own code and most Ruby code

**Files**: tokens.rb:398-413 (reverted in commit 2f290d2)

---

## 38. Regex Literal After Semicolon Parsed as Division (ARCHITECTURE ISSUE)

**Problem**: When a regex literal appears after a semicolon, it's incorrectly parsed as division because the tokenizer doesn't know that a semicolon was consumed by the parser.

**Example**:
```ruby
x = (raise if 2+2 == 3; /a/)  # /a/ should be regex, not division
```

**Parse Result** (INCORRECT):
```
[:/, [:+, 2, 2], [:/, 3, :a]]  # Both / treated as division
```

**Expected**:
```
[:callm, :Regexp, :new, "a"]  # /a/ should be Regexp.new("a")
```

**Root Cause - Architecture Problem**:

The issue stems from a fundamental architecture problem with how whitespace (including semicolons) is consumed:

1. **Semicolons are whitespace** (scanner.rb:146: `WS = [9,10,13,32,?#.ord,?;.ord]`)
2. **Both parser AND tokenizer consume whitespace independently**:
   - Parser calls `scanner.ws()` directly (parserbase.rb:52, 56)
   - Tokenizer calls `scanner.ws()` or `scanner.nolfws()` in `get()` (tokens.rb:806-812)
3. **No communication between them**: When the parser consumes a semicolon, the tokenizer has no way to know

**Investigation Timeline** (2025-11-16):

Attempted fix using sticky flags:
- Added `@last_ws_had_semicolon` flag to scanner
- Made `ws()` and `nolfws()` set flag to true when semicolon found
- Flag would "stick" (not reset to false) until explicitly cleared
- Tokenizer would check flag when seeing `/` to decide regex vs division

**Why It Failed**:
- Breaks `def parse_sexp; @sexp.parse; end` (parser.rb:666)
- After first `;`, flag is set
- But flag persists through `.parse` method call
- Causes parse errors on subsequent tokens
- Clearing the flag is fragile - when to clear? After every token? Only after `/`? After certain operators?

**The Real Problem**:
This is not a simple tokenization bug - it's an architectural issue. The parser and tokenizer both consume whitespace independently, with no coordination. Any state-based solution (flags, counters, etc.) will be fragile because:
1. Parser can call `ws()` multiple times before tokenizer sees next token
2. Tokenizer can call `nolfws()` and reset state parser had set
3. No clear ownership of when state should be cleared

**Proper Solution Would Require**:
- Refactoring whitespace handling so only ONE component consumes it
- OR: Making semicolons actual tokens instead of whitespace
- OR: Complete redesign of parser/tokenizer boundary

**Impact**:
- rubyspec/language/case_spec.rb: COMPILE FAIL (line 392: `when (raise if 2+2 == 3; /a/)`)
- Edge case - rarely encountered in practice

**Current Status**: **DEFERRED** - This requires significant architectural changes. The attempted hack with sticky flags is too fragile and breaks existing code.

**Workaround**: Avoid regex literals immediately after semicolons. Use `Regexp.new("pattern")` instead.

---

## 36. Keyword Argument Shorthand Not Supported (HIGH PRIORITY)

**Problem**: Ruby 3.1+ keyword argument shorthand `{a:}` meaning `{a: a}` is not supported in the parser.

**Impact**:
- rubyspec/language/hash_spec.rb: COMPILE FAIL (line 307: `h = {a:}`)
- rubyspec/language/def_spec.rb: COMPILE FAIL (keyword argument shorthand in method definitions)
- rubyspec/language/method_spec.rb: COMPILE FAIL (keyword argument shorthand in method calls)

**Example**:
```ruby
a, b, c = 1, 2, 3

# This syntax is not supported:
h = {a:}              # Should mean {a: a}
h = {a:, b:, c:}      # Should mean {a: a, b: b, c: c}

# Same for method calls:
call(a:)              # Should mean call(a: a)
```

**Impact**:
- hash_spec.rb fails at line 307: `h = {a:}`
- method_spec.rb fails at line 1454: `arr, h = call(a:)`
- Modern Ruby specs using this syntax fail to compile

**Root Cause**: The parser expects a value after `:` in hash/keyword argument syntax. The shorthand where the key name is also used as the variable name is not recognized.

**Parse Error**:
```
Missing value in expression / op: {assign/2 pri=7} / vstack: [] / rightv: [:hash, [:pair, [:sexp, :":h"], :a]]
```

**Affected Files**:
- rubyspec/language/hash_spec.rb (line 307)
- rubyspec/language/method_spec.rb (line 1454)

**Priority**: HIGH - This is common modern Ruby syntax, many specs use it

**Root Cause Analysis** (2025-11-16):
The issue is "value stack bleeding" in the shunting yard parser. When parsing `h = {a:}`:
1. Value stack shared across `=` and `{` subexpressions
2. Stack has `[h]` when entering hash literal
3. Sees `a`, pushes to stack: `[h, a]`
4. Sees `:` infix operator, pops TWO values: left=`h`, right=`a`
5. Creates `[:ternalt, h, a]` instead of `[:ternalt, a, nil]`
6. Result: `[:pair, :h, a]` instead of `[:pair, :a, a]`

This requires architectural changes to scope value stacks properly within subexpressions.

**Next Steps**:
1. ~~Modify parser/shunting yard to detect `:` followed by `,` or `}` or `)`~~ (blocked by value stack architecture)
2. **ARCHITECTURAL**: Fix shunting yard to isolate value stacks for `{:lp` subexpressions
3. Once architecture fixed, handle shorthand: `{a:}` → `[:ternalt, a, nil]` → `[:pair, :a, a]`

**Workaround**: Rewrite using explicit values: `{a: a}` instead of `{a:}`

---

## 40. Top-Level Instance Variables Generate Invalid Assembly Labels

**Problem**: Instance variables used at top-level scope (outside of methods or classes) generate assembly labels with the `@` prefix, which is invalid in assembly.

**Example**:
```ruby
# At top-level:
@dollar_dash_zero = $-0
$-0 = @dollar_dash_zero
puts "ok"
```

**Assembly Error**:
```
out/test_dollar_dash_assign.s:9435: Error: invalid char '@' beginning operand 2 `@dollar_dash_zero'
out/test_dollar_dash_assign.s:135601: Error: junk at end of line, first unrecognized character is `@'
```

**Assembly Output** (INVALID):
```asm
@dollar_dash_zero:
  .long 0
```

**Root Cause**: Instance variables at top-level are treated as globals and output with the `@` prefix intact in assembly labels. Assembly syntax doesn't allow `@` in label names.

**Workaround**: Put code inside methods, as instance variables inside methods work correctly:
```ruby
def test_method
  @dollar_dash_zero = $-0
  $-0 = @dollar_dash_zero
  puts "ok"
end
test_method
```

**Impact**:
- Affects rubyspec/language/predefined_spec.rb (which uses instance variables inside methods - works fine)
- Only affects test code written at top-level
- Production code typically uses methods, so this is rarely encountered

**Priority**: Low - Easily avoided by using methods, which is standard Ruby practice

**Test File**: test_dollar_dash_assign.rb (needs to be rewritten to use method)

---

## 41. RbConfig::CONFIG Cannot Be Resolved Statically

**Problem**: The compiler cannot resolve `RbConfig::CONFIG` at compile time, causing compilation failure with "Unable to resolve: RbConfig::CONFIG statically (FIXME)".

**Error Message**:
```
Unable to resolve: RbConfig::CONFIG statically (FIXME)
```

**Example**:
```ruby
require 'rbconfig'
RbConfig::CONFIG["EXTSTATIC"]  # Fails to compile
```

**Impact**: Any code that accesses RbConfig::CONFIG (common in library code) fails to compile.

**Test**: spec/rbconfig_access_spec.rb

**Status**: Not started
**Priority**: Medium

---

## 42. Duplicate Method Definitions Generate Assembly Errors

**Problem**: When a Ruby file defines the same method multiple times (which is allowed in Ruby - later definitions override earlier ones), the compiler generates duplicate assembly labels causing "symbol already defined" errors.

**Error Message**:
```
Error: symbol `__method_Object_method_missing' is already defined
Error: symbol `__method_Object_foo' is already defined
```

**Example**:
```ruby
def foo
  puts "first"
end

def foo  # Valid in Ruby - replaces first definition
  puts "second"
end

foo  # Should print "second"
```

**Root Cause**: The compiler generates assembly labels based on class name and method name only. When the same method is defined twice, it tries to emit the same label twice, causing an assembler error.

**Proposed Solution**: Add a suffix to subsequent method definitions (e.g., `__method_Object_foo`, `__method_Object_foo__2`, `__method_Object_foo__3`). The vtable should point to the latest version.

**Impact**: Primarily affects test code that redefines methods in different test cases. The full rubyspec/language/predefined_spec.rb fails to compile due to this issue.

**Workaround**: None - code must be restructured to avoid duplicate method definitions.

**Test**: rubyspec/language/predefined_spec.rb

**Status**: Not started
**Priority**: Low (only seen in predefined_spec.rb so far)

---

## 43. Percent Literal Delimiter Restrictions

**Problem**: Certain characters cannot be used as percent literal delimiters due to parsing ambiguities:
- `$` - Conflicts with global variable syntax
- `@` - Conflicts with instance variable syntax  
- `_` - Conflicts with identifier syntax
- Backslash `\` - Now supported (fixed 2025-11-17)

**Example**:
```ruby
# These work:
%Q{hello}
%Q(hello)
%Q[hello]
%Q!hello!

# These don't work:
%Q$hello$   # $ conflicts with $global_var syntax
%Q@hello@   # @ conflicts with @ivar syntax
%Q_hello_   # _ conflicts with identifiers

# This now works (as of 2025-11-17):
%Q\hello\   # Backslash delimiter fixed
```

**Root Cause**: When `$` is used as a delimiter in percent literals with interpolation, the closing `$` after `#{...}` creates ambiguity - it could be:
1. The closing delimiter (correct)
2. The start of a global variable (incorrect, but gets parsed)

Similar issues exist for `@` (instance vars) and `_` (identifiers).

**Fix Applied (2025-11-17)**:
- Backslash delimiter now works correctly - escape handling is skipped when backslash is the delimiter
- `$`, `@`, and `_` are excluded from allowed delimiters to avoid ambiguity
- Error reporting improved: shows position at start of percent literal, not EOF

**Impact**:
- Most percent literals work correctly
- Rare delimiters like `$`, `@`, `_` are not supported
- string_spec.rb now compiles (was COMPILE FAIL due to `%\...\` and `%$...$`)

**Test**: 
- `test_bs.rb` - backslash delimiter
- rubyspec/language/string_spec.rb - comprehensive percent literal tests

**Status**: ✅ FIXED (2025-11-17) - backslash delimiter supported, problematic delimiters excluded

**Priority**: Low - affected delimiters are rarely used

**Commit**: b187fd5 "Fix percent literal parsing bugs"

---
## 44. Percent Literals in Method Arguments Require Parentheses

**Problem**: Percent literals like `%Q{...}` cannot be used as arguments to method calls without parentheses.

**Example**:
```ruby
# This doesn't work - generates "undefined reference to Q"
eval %Q{puts "hello"}

# Workaround - use parentheses:
eval(%Q{puts "hello"})
```

**Root Cause**: The tokenizer uses the heuristic `@first || prev_lastop` to distinguish percent literals from modulo operators. After an identifier like `eval`, neither condition is true, so `%Q` is parsed as modulo (`%`) followed by identifier (`Q`).

**Why It's Hard to Fix**: Adding lookahead to detect `%Q{` patterns is error-prone because:
1. Scanner only supports 1-character lookahead via `peek`
2. Using `get`/`unget` for lookahead breaks position tracking and causes parse errors elsewhere (e.g., hash.rb)
3. The distinction between `%` (modulo) and `%Q{` (percent literal) requires 2-3 character lookahead

**Workaround**: Use parentheses for method calls:
- `eval(%Q{...})` instead of `eval %Q{...}`
- `foo(%w[a b c])` instead of `foo %w[a b c]`

**Impact**:
- alias_spec.rb: COMPILE FAIL due to `eval %Q{...}` patterns (lines 59, 96)
- Most code unaffected - parentheses are common style anyway

**Status**: ❌ NOT FIXED - workaround available (use parentheses)

**Priority**: Low - affects rare edge case, easy workaround

**Test**: test_eval_percent_q.rb - demonstrates the issue

**Related**: Issue #43 (Percent Literal Delimiter Restrictions)

---
## 45. Splat with Begin Block in Array Indexing

**Problem**: Using splat operator with a begin block inside array indexing `[]` causes a syntax error.

**Example**:
```ruby
h = {k: 10}
x = h[*begin [:k] end]  # Syntax error
```

**Error Message**: "Syntax error. [{array/1 pri=97}]"

**Root Cause**: The parser's handling of array indexing `[]` doesn't properly support complex expressions with splat + begin blocks. The `*begin ... end` pattern works in assignments but not inside `[]`.

**Workaround**: Extract the expression to a variable first:
```ruby
h = {k: 10}
keys = *begin [:k] end
x = h[*keys]
```

**Impact**:
- rubyspec/language/assignments_spec.rb: COMPILE FAIL (line 261: `$spec_b[*begin 1; [:k] end] += 10`)
- Rare pattern - not commonly seen in production code

**Status**: ❌ NOT FIXED - workaround available (extract to variable)

**Priority**: Low - affects edge case, easy workaround

**Test**: spec/array_index_splat_begin_spec.rb

---
## 46. Nested Constant Assignment in Closures Not Supported

**Problem**: Assigning to nested constants (e.g., `A::B::CONST = value`) inside closures/blocks causes "Expected an argument on left hand side of assignment" error.

**Example**:
```ruby
it "test" do
  ConstantSpecs::ClassB::CS_CONST101 = :value  # Error: got subexpr
end
```

**Error Message**:
```
Expected an argument on left hand side of assignment - got subexpr,
(left: [[:index, :__env__, 1], [[:index, :__env__, 1], :ConstantSpecs, :ClassB], :CS_CONST101],
 right: [:sexp, :__S_const101_1])
```

**Root Cause**: The compiler doesn't recognize nested constant paths as valid assignment targets when they appear in closure contexts. The AST structure `[:index, ...]` for `A::B::C` is treated as "subexpr" rather than a valid lvalue.

**Workaround**: Avoid nested constant assignments in closures. Define constants at the top level instead.

**Impact**:
- rubyspec/language/constants_spec.rb: COMPILE FAIL (line 556: `ConstantSpecs::ClassB::CS_CONST101 = :const101_1`)

**Status**: ❌ NOT FIXED - requires compiler changes to recognize nested constant paths as valid assignment targets

**Priority**: Low - dynamically assigning nested constants in closures is rare

---

## 47. Argument Name Rewritten to Environment Index Reference

**Problem**: Was: During closure rewriting, method parameter names were incorrectly rewritten to environment index references.

**Status**: ✅ PARTIALLY FIXED - The "Arg.name must be Symbol" error is resolved

**What was fixed**:
- Added `:defm` handling in `rewrite_env_vars` to skip parameter list rewriting
- commit 99f3a8d fixes the specific error

**Remaining issues in hash_spec.rb**:
- After the fix, hash_spec now fails with different error:
  ```
  Expected an argument on left hand side of assignment - got subexpr,
  (left: [:comma, [:index, :__env__, 7], [:index, :__env__, 8]], right: ...)
  ```
- This appears to be destructuring assignment where both LHS elements are environment references
- The compiler doesn't recognize `a, b = value` where a and b are env indices

**Impact**:
- hash_spec.rb: Still COMPILE FAIL (different error)
- def_spec.rb: Still COMPILE FAIL (duplicate symbol definitions)

**Note**: The closure rewriting now correctly skips :defm parameter lists. The remaining issues are:
1. Destructuring with environment references as LHS
2. Duplicate method symbol definitions in certain specs

---

## 48. Global Namespace for Modules (module ::Name)

**Problem**: Was: Using the global scope operator `::` to reopen a module (like `module ::Private`) generated invalid assembly with literal AST nodes.

**Example**:
```ruby
module Private
end

module ::Private  # This was broken - now FIXED
  # reopen in global scope
end
```

**Status**: ✅ FIXED - Parser and transform now handle `module ::Name` global namespace syntax

**What was fixed**:
- parser.rb: Added `::` prefix handling to `parse_module` and `parse_module_body`
- transform.rb: Added `[:global, name]` handling in `build_class_scopes` for modules
- private_spec.rb: Now compiles successfully (has runtime failures for missing Object#methods)

**Note**: Combined with the previous `class ::A` fix, both class and module global namespace definitions are now fully supported.

---

## 49. Internal AST Nodes Emitted as Method Calls

**Problem**: The compiler sometimes emits internal AST node names (like `hash_splat`, `ternalt`, `proc`) as method calls instead of compiling them properly. These should never appear as method names - they are internal compiler constructs.

**Example errors from keyword_arguments_spec.rb**:
```
undefined method 'hash_splat' for #<Object:...>
undefined method 'ternalt' for #<Object:...>
undefined method 'proc' for #<Object:...>
```

**Internal AST nodes that should never be method calls**:
- `:hash_splat` - Hash spread operator `**hash`
- `:ternalt` - Ternary else branch `? : `
- `:proc` - Proc/block creation
- `:splat` - Array spread operator `*array`
- `:to_block` - Block conversion `&block`

**Root Cause**: Code generation is missing handlers for these AST nodes in certain contexts. When the compiler encounters an unhandled node type, it falls through to treating it as a method call.

**Impact**: Specs that use these constructs will compile but fail at runtime with "undefined method" errors for what should be internal compiler operations.

**Status**: Not fixed. Requires investigation into which code paths are failing to handle these nodes.

**Affected specs**: keyword_arguments_spec.rb (now compiles after `call $2` fix but has runtime failures)

---

## Multi-Statement Parentheses - Semicolons Work, Newlines Don't

**Problem**: Ruby allows multiple statements inside parentheses, separated by semicolons or newlines. Semicolons work, but newlines don't:

```ruby
# This WORKS:
a = (x = 1; y = 2)  # a gets value of y (2)

# This DOESN'T WORK:
a = (
  x = 1
  y = 2
)
# Error: Parses as function call (x = 1)(y = 2) instead of two statements
```

**Root Cause**: The shunting yard parser treats newlines as whitespace inside parentheses. When the tokenizer consumes whitespace via `src.ws if lp_on_entry` (shunting.rb:374), newlines are consumed without recording that a statement break occurred. The subsequent token is then treated as part of the previous expression.

**Attempted Fix (2025-11-19)**: Track newlines in consumed whitespace and inject `:do` operator:
1. Added `@had_newline_in_ws` flag to track newlines
2. Modified whitespace consumption to peek for newlines before consuming
3. Injected `:do` operator when newline found after a value in parentheses context
4. Set `opstate = :prefix` and `possible_func = false` after injection

**Why It Failed**: Scanner position tracking failed when using `scanner.position = pos` to rewind after peeking, causing a segfault in selftest. The basic approach was correct:
```
DEBUG: Injecting :do separator, ostack=[{/0 pri=99}, {assign/2 pri=7}], vstack=[:x, :a, 1]
DEBUG: After reduce, ostack=[{/0 pri=99}], vstack=[:x, [:assign, :a, 1]]
```
The `:do` was correctly injected and reduced the `=` operator, but the scanner rewind corrupted state.

**Key Insight**: The issue is that `newline_before_current` is set by the tokenizer during its own whitespace handling, but inside parentheses the shunting yard calls `src.ws` which consumes whitespace (including newlines) independently, without updating this flag.

**Rejected Solution 1**: Adding a `parse_paren_exps` method in parser.rb that the shunting yard calls when encountering `(` in non-call context. This approach was rejected because:

1. **Architectural violation**: It bypasses the shunting yard algorithm for parentheses, creating an inconsistent parsing path where some parentheses are handled by the parser and others by the shunting yard
2. **Breaks compositionality**: The shunting yard should be the single authority for expression parsing. Having the parser take over mid-expression creates fragile special cases
3. **Wrong abstraction level**: Statement separation (`;`) is a parser concern, not an expression parser concern. Mixing these responsibilities creates coupling that makes future changes harder

**Rejected Solution 2**: Making `;` a global infix operator that produces `:do` blocks, removing it from the WS (whitespace) constant. This approach was rejected because:

1. **Context-sensitivity**: Semicolon has different semantics in different contexts - inside parentheses it should create `:do` blocks, but inside method bodies it's already handled by the parser. Making it a global operator breaks `def foo; end` patterns
2. **Breaks existing code**: Code like `while condition do; end` fails to parse because `;` is now seen as an operator expecting operands
3. **Scope confusion**: The operator would need to know whether it's inside parentheses vs inside a block, which the shunting yard doesn't track

**Further Attempt (2025-11-19)**: Adding newline as operator with special handling:

1. Added `"\n"` to Operators hash as `:do` operator like `;`
2. Modified shunting.rb to use `nolfws` inside `()` (not `{}`, `[]`, or function calls)
3. Skip newlines in prefix position (after `(`, after `;`)
4. Push nil for trailing `;` or `\n` before `)`
5. Push nil when inhibiting with minarity 0 prefix operator

**Result**: Semicolon works correctly, but newline-as-operator causes a runtime bug where a Hash object is passed to method_missing instead of a Symbol. The error manifests as:
```
Unhandled exception: undefined method '{}' for {}
```

The `sym` argument to method_missing is actually a Hash, not a Symbol. This happens specifically when `"\n"` is returned as an operator from the tokenizer. Moving the newline operator to a constant in tokens.rb (not in Operators hash) doesn't fix the issue. The root cause is not yet understood - something in the compilation creates a Hash where a Symbol should be passed.

**Current Workaround**: The shunting.rb changes are kept (they fix other issues with `;` handling), but newline-as-operator is disabled. Use semicolons or `begin...end` blocks:

```ruby
# Use semicolons:
a = (x = 1; y = 2)

# Or use begin...end:
a = begin
  x = 1
  y = 2
end
```

**Future Work**: Debug why returning newline as an operator causes Hash to appear in method_missing. The issue may be related to vtable thunk generation or symbol table handling.

**Priority**: LOW - rare usage pattern with easy workarounds

---

## 50. Bootstrap Issue: Array Operations in depth_first Blocks Crash - FIXED

**Problem**: When writing transform functions in transform.rb that use `Array#<<` or build complex arrays inside `depth_first` blocks, the compiled compiler crashes with a jump to address 0.

**Root Cause**: Using a local variable named `assign` conflicted with the `:assign` symbol in the AST, causing the compiled compiler to generate incorrect code. The issue was NOT about array operations - it was a variable naming issue.

**Fix**: Rename the variable from `assign` to `asgn` to avoid the name conflict. The transform now works correctly in both MRI and the compiled compiler.

**Status**: FIXED. The `rewrite_default_args` transform is now enabled and working:
- Moves default argument expressions into method body as if/assign statements
- Uses `numargs` to check argument count at runtime
- Properly preserves `:default` marker for arity calculation

---

## 51. Procs in Class Bodies Inside Lambdas Fail with Undefined Closure Variables - FIXED

**Problem**: When a proc/lambda is defined inside a class/module body that is itself inside another lambda or method, the closure variables `__env__`, `__closure__`, and `__tmp_proc` are not properly set up.

```ruby
# This fails to compile:
require 'rubyspec_helper'

def run_specs
  describe("test") do
    it "test" do
      class MyClass
        OBJ = Object.new
        OBJ.instance_eval do    # <- This proc fails
          def foo; end
        end
      end
    end
  end
end
```

**Errors**:
```
undefined reference to `__tmp_proc'
undefined reference to `__env__'
undefined reference to `__closure__'
```

**Root Cause**: The `rewrite_lambda` transformation is called from `rewrite_let_env`, which only processes `:defm` (method definition) nodes. When a proc appears in a class body that's inside a lambda, the class body is compiled in `ClassScope` context, not the enclosing lambda's scope. The proc transformation generates code that references closure variables (`__env__`, `__tmp_proc`, `__closure__`) as if they were available, but they're not in the class scope.

The parse tree shows the structure:
```
(defun "__lambda_L239" (self __closure__ __env__)
  (let ()                    # <- Empty let, no local vars
    (class DefSpecNested ... (
      (callm OBJ instance_eval () (do
        (assign (index __env__ 0) (stackframe))  # <- Uses __env__ from class context
        (assign __tmp_proc ...)                   # <- Uses __tmp_proc from class context
        ...
      ))
    ))
  ))
```

The lambda `L239` takes `__env__` as a parameter, but the code in the class body tries to use it directly, which compiles to a global symbol reference instead of a local variable access.

**Impact**: Cannot use procs/lambdas inside class/module bodies that are themselves inside methods or lambdas. This affects:
- mspec-style specs with `describe`/`it` blocks containing classes
- Any nested structure like `method { class Foo { block { } } }`

**Fix**: Modified `ClassScope` to track the enclosing local scope separately from the namespace parent:
1. Added `@local_scope` field to `ClassScope` for accessing enclosing method/block variables
2. Updated `ClassScope#get_arg` to check `@local_scope` for `:lvar` and `:arg` lookups before falling back to namespace scope
3. Modified `compile_class` to pass the incoming scope as `local_scope` when creating or reopening a class

This allows procs in class bodies to correctly resolve variables like `__env__`, `__tmp_proc`, and `__closure__` from the enclosing method/lambda scope.

**Status**: FIXED

**Test Case**: `test_class_lambda_method.rb`

---


## 52. Module/Class Reopening Inside Methods Creates Duplicate Scope - FIXED

**Problem**: When a module/class is defined at global scope and then reopened inside a method, the compiler created a duplicate scope with a different name (e.g., `Object__ClassSpecs` instead of `ClassSpecs`), causing constant lookups to fail.

**Example**:
```ruby
module ClassSpecs
  class B; end
end

def run_specs
  # Reopening ClassSpecs here created Object__ClassSpecs
  module ClassSpecs
    Number = 12
  end
  
  describe("test") do
    it "uses B" do
      ClassSpecs::B.new  # Error: undefined reference to `B'
    end
  end
end
```

**Root Cause**: When `compile_class` was called from inside a method, it walked up the scope chain and found the Object ClassScope as the parent. It then computed `fully_qualified_name = "Object__ClassSpecs"` which didn't exist in `@classes`, so it created a new scope. This new scope was registered in Object's `@constants[:ClassSpecs]`, causing later lookups to find the wrong scope that didn't have the nested classes registered.

**Affected Specs**:
- rubyspec/language/class_spec.rb - Had many `undefined reference to 'B'`, `'C'`, `'D'` errors
- Any rubyspec file with modules reopened inside `def run_specs`

**Fix**: Modified `compile_class.rb` with several improvements:

1. Check if class/module exists with simple name when parent scope is Object:
```ruby
# Only do this for symbol names (not runtime-computed names like [:index, :__env__, 4])
if !cscope && parent_scope.is_a?(ModuleScope) && parent_scope.name == "Object" && name.is_a?(Symbol)
  cscope = @classes[name]
  fully_qualified_name = name if cscope
end
```

2. Added `explicit_namespace` flag for `class Foo::Bar` syntax to prevent double prefixing:
```ruby
# When using explicit namespace syntax (class Foo::Bar), the name already contains
# the full path, so don't add parent scope prefix
if explicit_namespace
  fully_qualified_name = name.to_sym
elsif parent_scope.is_a?(ModuleScope)
  fully_qualified_name = "#{parent_scope.name}__#{name}".to_sym
else
  fully_qualified_name = name.to_sym
end
```

**Status**: FIXED (with remaining edge cases in Issue 53)

**Files Modified**: compile_class.rb:206, 229-230, 254-261, 264-268

**Remaining Issues**:
- `class Foo::Bar < L` inside reopened module still has superclass lookup issues (see Issue 53)
- Constants defined in eigenclasses inside lambdas aren't found

---


## 53. Superclass and Constant Lookup in Nested/Reopened Classes

**Problem**: Several issues remain with superclass and constant resolution when classes/modules are reopened inside lambdas or methods:

1. **Superclass Lookup**: When inheriting from a class inside a reopened module, the superclass gets double-prefixed:
```ruby
module ClassSpecs
  class L; end
end

def run_specs
  module ClassSpecs  # Reopening
    class M < L     # Should find ClassSpecs__L
    end             # Actually generates reference to ClassSpecs__ClassSpecs__L
  end
end
```

2. **Constants in Eigenclasses Inside Lambdas**:
```ruby
class << obj
  CONST = 123
end
-> { CONST }.call  # Error: undefined reference to 'CONST'
```

3. **Runtime Constant Assignment**:
```ruby
# Inside lambda with closure-captured parent
obj::FOO = 1  # Error: Expected argument on left hand side of assignment
```

**Root Cause**:
1. Superclass symbol `:L` needs to be resolved to fully qualified name `ClassSpecs__L` during transform or compile phase, but currently uses simple symbol lookup
2. Constants defined in eigenclasses need to be accessible from the enclosing scope chain
3. Runtime constant assignment with non-symbol parent not supported

**Affected Specs**:
- rubyspec/language/class_spec.rb - `ClassSpecs__ClassSpecs__L` errors
- rubyspec/language/metaclass_spec.rb - CONST undefined
- rubyspec/language/singleton_class_spec.rb - CONST undefined
- rubyspec/language/constants_spec.rb - runtime constant assignment

**Status**: OPEN

---


## Pattern Matching with Nested Closures (CRITICAL)

**Issue**: Pattern-bound variables inside closures are not properly captured in `__env__` if they need to be accessed by nested closures.

**Root cause**: The transformation pipeline order is:
1. `preprocess` → `rewrite_let_env` → `find_vars` + `rewrite_env_vars`
2. `compile` → `rewrite_pattern_matching` (creates variable bindings)

Since `find_vars` runs BEFORE `rewrite_pattern_matching`, it doesn't see pattern-bound variables and won't add them to `__env__`. The fix in transform.rb:704 skips rewriting `:pattern_key` variable names to prevent literal `[:index, :__env__, N]` in assembly, but this means pattern-bound variables won't be captured for nested closures.

**Example that fails**:
```ruby
result = nil
1.times {
  case {x: 42}
  in {x:}
    1.times { result = x }  # ERROR: undefined method 'x'
  end
}
puts result  # Should print 42, but fails
```

**What works**:
- Pattern matching at closure top level (no nested closures)
- Pattern-bound variables used directly in the same closure

**What doesn't work**:
- Pattern-bound variables accessed from nested closures
- Pattern-bound variables passed to methods that create closures

**Potential fix**: Need to either:
1. Run `rewrite_pattern_matching` before `rewrite_let_env` (major reordering)
2. Have `rewrite_pattern_matching` insert proper `[:index, :__env__, N]` nodes directly
3. Add a second pass after pattern matching to identify captured pattern variables

---

## 55. Heredoc String Interpolation Not Implemented

**Status**: ❌ NOT IMPLEMENTED

**Problem**: Double-quoted heredocs (`<<MARKER`, `<<"MARKER"`, `<<~MARKER`) do not expand `#{...}` interpolations. The interpolation syntax is kept as a literal string.

```ruby
$x = "world"
puts <<END
hello #{$x}
END
# Expected: "hello world\n"
# Actual: "hello #{$x}\n"
```

**Root Cause**: Heredoc parsing in `tokens.rb` (lines 912-1016) reads the heredoc body as a plain string and returns it directly without calling the `handle_interpolation()` function from `quoted.rb` that processes `#{...}` syntax.

**What works**:
- Single-quoted heredocs (`<<'MARKER'`, `<<-'MARKER'`, `<<~'MARKER'`) - correctly preserved as literal
- Regular double-quoted strings with interpolation: `"hello #{$x}"`

**What doesn't work**:
- Double-quoted heredocs: `<<MARKER`, `<<"MARKER"`, `<<~MARKER`
- Any heredoc with `#{...}` interpolation

**Potential fix**: Modify heredoc parsing in `tokens.rb` to:
1. Check if heredoc is single-quoted (no interpolation) or double-quoted (interpolation)
2. For double-quoted heredocs, process the body through `Quoted.handle_interpolation()` similar to regular strings
3. Return the interpolated expression tree instead of a plain string constant

**Impact**: 10+ rubyspec tests in heredoc_spec.rb fail due to this issue.

**Priority**: MEDIUM - Single-quoted heredocs work, regular strings with interpolation work.

---

## 56. POSIX Character Class Integration Causes Self-Hosting Crash

**Status**: ⚠️ PARTIALLY IMPLEMENTED

**Problem**: While the `__posix?` helper method for POSIX character classes compiles and works correctly, integrating it into the regexp character class matching code (`match_from` and `match_atom`) causes selftest-c to crash with a segmentation fault.

**What works**:
- The `__posix?` helper method itself (committed in fbb7a85)
- Compiling and running standalone programs with POSIX classes when using MRI-compiled compiler
- Regular character classes `[a-z]`, `[^0-9]`, etc.

**What doesn't work**:
- When integration code is added to handle `[[:alpha:]]` in `match_from` or `match_atom`, selftest-c crashes
- This happens regardless of whether the code uses:
  - Nested while loops inline
  - Helper method calls (`__skip_char_class`, `__skip_posix_class`)
  - Flat if/elsif chains

**Symptoms**: The compiled compiler (out/driver) segfaults when trying to compile test/selftest.rb.

**Root Cause**: Unknown. Appears to be a compiler bug triggered by certain code patterns during self-hosting. The bug is not triggered when using the MRI-compiled compiler, only when the compiled compiler compiles code.

**Workaround**: POSIX character classes like `[[:alpha:]]` are not supported in the regexp engine. The `__posix?` helper is committed and ready for integration once the underlying compiler bug is identified and fixed.

**Related**: Similar behavior was reported with "11 elsif branch" methods causing crashes, though that issue appeared transient.

**Priority**: LOW - Basic regexp support works. POSIX classes are a nice-to-have feature.

---

## 57. Named Captures Integration Causes Self-Hosting Crash

**Status**: ⚠️ BLOCKED BY COMPILER BUG

**Problem**: Similar to issue #56 (POSIX classes), adding named capture support `(?<name>...)` to the regexp engine causes selftest-c to crash during self-hosting.

**What was implemented**:
- Parsing named captures in Regexp#initialize via `__parse_named_captures`
- Regexp#names returns array of capture names
- Regexp#named_captures returns hash of name => [indices]
- MatchData#[] supports symbol/string access for named captures
- MatchData#named_captures returns hash of name => value

**What works**:
- All named capture features work correctly when compiled with MRI-compiled compiler
- Code passes all functionality tests

**What doesn't work**:
- When the compiled compiler tries to compile test/selftest.rb, it segfaults
- This is the same pattern as POSIX class integration (#56)

**Root Cause**: Unknown. Appears to be the same underlying compiler bug that affects POSIX class integration. Something about certain code patterns (possibly nested control flow, method calls in loops, or specific combinations) triggers a bug during self-hosting.

**Workaround**: Named captures `(?<name>...)` are not supported. Use numbered captures `(...)` with `m[1]`, `m[2]` instead.

**Priority**: LOW - Numbered captures work fine. Named captures are a convenience feature.
