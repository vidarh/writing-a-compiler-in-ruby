# BUGAUDIT Test Specification

## Test Suite Location

All test files go in `spec/` with the naming convention `spec/bug_<category>_spec.rb`.

Files to create:

| File | Category |
|------|----------|
| `spec/bug_yield_in_nested_block_spec.rb` | Cat 1: yield/block.call in nested contexts |
| `spec/bug_variable_name_collision_spec.rb` | Cat 2: Variable-name collision / env rewrite |
| `spec/bug_ternary_expression_spec.rb` | Cat 3: Ternary expression evaluation |
| `spec/bug_block_given_nested_spec.rb` | Cat 4: block_given? in nested lambdas |
| `spec/bug_self_recursive_lambda_spec.rb` | Cat 5: Self-recursive lambda / method extraction |
| `spec/bug_parser_divergence_spec.rb` | Cat 6: Parser divergence (MRI vs self-hosted) |
| `spec/bug_break_in_block_spec.rb` | Cat 7: break in block register corruption |

## Design Requirements

### No mocking or dependency injection needed

These specs test **language-level constructs** (yield, variable scoping, ternary expressions, break, block_given?, lambdas). They do not exercise compiler internals via API calls. Each spec defines plain Ruby classes/methods that exercise the construct the `@bug` marker claims is broken, then checks the result.

The test framework is the project's custom mspec-compatible runner (`rubyspec_helper.rb`) which provides `describe`, `it`, `.should`, `.should ==`, `.should be_true`, `.should be_false`, `.should be_nil`, and `.should raise_error`. No external gems, no network access, no filesystem dependencies.

### No refactoring needed for testability

Every `@bug` workaround describes a **Ruby language construct** that the compiler cannot compile correctly. The specs test whether the construct works at the language level. The compiler itself is the system under test (it compiles and runs the spec). No code needs to be refactored to enable testing.

## Required Test Coverage

### spec/bug_yield_in_nested_block_spec.rb (Category 1)

Tests whether `yield` works inside nested blocks/lambdas when the enclosing method takes `&block`.

**Scenarios (all must be present):**

1. **yield inside a nested do-block**: Define a method that takes `&block`, internally calls another method that takes a block, and uses `yield` inside that inner block. Verify the yielded value reaches the caller's block. This directly mirrors `emitter.rb:409-410` where `with_register` takes a block and tries to yield from inside it.

   ```
   class Foo
     def with_thing
       # some setup
       [1].each do |x|
         yield x   # yield from inside nested block
       end
     end
   end
   Foo.new.with_thing { |v| v }.should == 1
   ```

2. **yield with multiple arguments from nested block**: Define a method that takes `&block`, iterates over a collection, and yields two values from inside the iteration block. Verify both values are received. This mirrors `globals.rb:46-48` where `yield f[0], f[1]` gets miscompiled as a "comma" call.

   ```
   def multi_yield(&block)
     pairs = [[1, 2], [3, 4]]
     pairs.each do |pair|
       yield pair[0], pair[1]
     end
   end
   ```
   Call it, collect results, verify both arguments arrive correctly.

3. **yield from method that received block via &block, inside with_register-style pattern**: Method takes `&block`, conditionally enters one of two nested blocks, and yields from inside. This mirrors the exact `with_register_for` pattern in `emitter.rb:398-420`. The method should have an `if/else` where both branches contain a nested block that yields.

4. **yield from doubly-nested block**: Method takes `&block`, calls a method that takes a block, and inside THAT block calls another method that takes a block, and yields from the innermost. This is the extreme case.

5. **Edge case: yield with no arguments from nested block**: Verify `yield` with zero arguments works inside a nested block (simpler case that should definitely pass if the general case does).

**Expected result for confirmed bug:** Compilation error, segfault, or wrong value returned. If the spec passes, the yield-in-nested-block bug is stale for that particular variant.

### spec/bug_variable_name_collision_spec.rb (Category 2)

Tests whether a local variable with the same name as a method on `self` (or a widely-used method) gets incorrectly rewritten inside blocks/lambdas.

**Scenarios (all must be present):**

1. **Local var shadows method name inside block**: Define a class with a method `rest`. In another method, assign a local variable named `rest`, then use it inside a block passed to `each`. Verify the local `rest` is read correctly (not rewritten to a method call on `self`). This mirrors `compiler.rb:619-623` where `rest` conflicted with `arg.rest`.

   ```
   class VarCollision
     def rest; "method_rest"; end
     def test
       rest = "local_rest"
       [1].each { |x| rest }  # should return "local_rest"
     end
   end
   ```

2. **Local var shadows method name inside lambda**: Define a class with a method `reg`. In another method, assign a local `reg` inside a lambda. Verify it reads the local, not the method. This mirrors `regalloc.rb:310-312` where `reg` was renamed to `xreg`.

3. **String interpolation with outer-scope variable inside block**: Define a method with a local `op`, then use `"set#{op.to_s}"` inside a block. Verify the interpolation uses the outer `op`, not some block parameter or method. This mirrors `compile_comparisons.rb:9-12`.

4. **Argument name collides with constructor/keyword**: Define a method that takes an argument named `range`. Verify it works as a plain argument and doesn't trigger any range constructor rewrite. This mirrors `lib/core/enumerator.rb:64-66`.

5. **Variable not initialized to nil without explicit assignment**: Define a method where a local variable `r` is conditionally assigned (only in an `if` branch), then returned. Without explicit `r = nil`, verify `r` is `nil` when the condition is false. This mirrors `function.rb:123-124`.

   ```
   def conditional_init(flag)
     r = nil  # workaround line
     r = 42 if flag
     r
   end
   ```
   Test with the explicit `r = nil` first (should pass). Then the spec should also test the construct WITHOUT the `r = nil` line to see if the bug reproduces.

6. **Variable named same as method, used in nested lambda with method call on object**: The most complex case combining elements — a class with method `dividend`, a local `dividend` assigned in an outer method, used inside a nested `do` block after another `do` block. This mirrors `compile_arithmetic.rb:120-124`.

7. **Edge case: method name collision across multiple nesting levels**: Variable `name` defined in outer method, used in lambda, which is inside another lambda. Checks deep closure capture with naming collisions.

### spec/bug_ternary_expression_spec.rb (Category 3)

Tests whether ternary expressions evaluate correctly in cases the compiler historically got wrong.

**Scenarios (all must be present):**

1. **Ternary with `||` in condition**: `a || b ? c : d` where `a` is truthy. The compiler historically evaluates this as `false`. This mirrors `treeoutput.rb:235-237`.

   ```
   comma = true
   block = false
   result = comma || block ? "yes" : "no"
   result.should == "yes"
   ```

2. **Ternary with `||` where first operand is falsy**: `a || b ? c : d` where `a` is false but `b` is true. Verify the `||` evaluates correctly before the ternary.

3. **Ternary with `||` where both are falsy**: `nil || false ? "yes" : "no"` should return `"no"`.

4. **Ternary assigned to variable used in subsequent method call**: `args = lv ? lv + rightv : rightv` where `lv` is a local variable and `rightv` is an array. The result is then used in a method call. This mirrors `treeoutput.rb:262-267`.

   ```
   lv = [1, 2]
   rightv = [3, 4]
   args = lv ? lv + rightv : rightv
   args.should == [1, 2, 3, 4]
   ```

5. **Ternary assigned to variable, lv is nil**: Same as above but `lv = nil`, verifying the else branch.

   ```
   lv = nil
   rightv = [3, 4]
   args = lv ? lv + rightv : rightv
   args.should == [3, 4]
   ```

6. **Ternary with array wrapping in condition**: `lv = val; lv = [lv] if lv && !lv.is_a?(Array)` — while this is an `if` not a ternary, the original code was a ternary. Test the ternary version: `lv = (lv && !lv.is_a?(Array)) ? [lv] : lv`.

7. **Edge case: nested ternary**: `a ? (b ? c : d) : e` to verify the parser handles nested ternaries.

### spec/bug_block_given_nested_spec.rb (Category 4)

Tests whether `block_given?` returns the correct value when checked inside a nested block/lambda.

**Scenarios (all must be present):**

1. **block_given? inside a nested do-block (block passed)**: Method takes `&block`, checks `block_given?` inside a `[1].each do ... end` block. Should return `true` when a block is passed. This mirrors `compile_arithmetic.rb:115-118`.

   ```
   def check_bg(&block)
     result = nil
     [1].each do |x|
       result = block_given?
     end
     result
   end
   check_bg { 42 }.should == true
   ```

2. **block_given? inside a nested do-block (no block passed)**: Same method called WITHOUT a block. Should return `false` inside the nested block.

3. **block_given? captured to local before entering nested block (the workaround pattern)**: Verify the workaround pattern itself works. `bg = block_given?` before entering block, then use `bg` inside. This should always work and serves as the control case.

4. **block_given? inside doubly-nested block**: Method takes `&block`, enters `[1].each do ... [2].each do ... end ... end`, checks `block_given?` at the innermost level. This is a stricter test.

5. **Edge case: block_given? inside lambda inside method**: Method takes `&block`, defines `f = lambda { block_given? }`, calls `f.call`. Verify the result (note: in MRI, `block_given?` inside a lambda refers to the lambda's own block status, not the enclosing method's — the spec should document expected MRI behavior).

### spec/bug_self_recursive_lambda_spec.rb (Category 5)

Tests whether self-recursive lambdas and iteration-with-method-call lambdas compile correctly.

**Scenarios (all must be present):**

1. **Self-recursive lambda**: Define a method containing a local lambda that calls itself recursively (e.g., factorial or tree traversal). Verify it produces the correct result. This mirrors `compiler.rb:563-565` where `compile_case_test` was extracted from a recursive lambda.

   ```
   def test_recursive_lambda
     fact = lambda { |n| n <= 1 ? 1 : n * fact.call(n - 1) }
     fact.call(5)
   end
   test_recursive_lambda.should == 120
   ```

2. **Lambda that iterates and calls a method on self**: Define a class with a method that creates a lambda which calls `each` on a collection and invokes another instance method from inside the iteration. This mirrors `compile_class.rb:113-116` where `compile_ary_do` was extracted because the lambda iterating + calling `compile_do` failed.

   ```
   class LambdaIter
     def process(item); item * 2; end
     def run(items)
       results = []
       items.each do |e|
         results << process(e)
       end
       results
     end
   end
   ```

3. **Lambda assigned to local, called multiple times**: Verify a lambda stored in a local variable can be called more than once without corruption.

4. **Method that was extracted as a workaround — the inline form**: Define a method containing code that was originally a separate method but should work as an inline block. Specifically: `items.each { |e| self.other_method(e) }` inside a method, where `other_method` is on the same object.

5. **Edge case: mutually recursive lambdas**: Two lambdas that call each other. This is a stricter variant of the self-recursive case.

### spec/bug_parser_divergence_spec.rb (Category 6)

Tests constructs where the self-hosted parser produces different results than MRI parsing.

**Scenarios (all must be present):**

1. **Method call with arithmetic expression as argument**: `obj.method(x.size + 1)` where `x` is an array or other object with `.size`. This mirrors `compiler.rb:1231-1234` where `@e.with_local(vars.size+1)` was parsed incorrectly.

   ```
   class ParserTest
     def take(n); n; end
   end
   arr = [1, 2, 3]
   ParserTest.new.take(arr.size + 1).should == 4
   ```

2. **Method call with arithmetic on method result, inside block**: Same as above but inside a `do` block, to test whether block context affects parsing.

3. **Method call with subtraction on method result**: `obj.method(x.size - 1)` — subtraction might parse differently from addition due to unary minus ambiguity.

4. **Chained method call with arithmetic**: `obj.foo.bar(x.size + 1)` — additional chaining to stress the parser.

5. **Conditional array assignment with concat**: `arr = pos.concat(ret)` where `ret` might or might not be an Array. This mirrors `parser.rb:797-800`. Test that the expression `E[pos].concat(ret)` works when `ret` is an Array and when it is not.

   Note: The `E[]` construct is compiler-internal. For the spec, test the general pattern: calling `.concat` on an array conditionally based on `is_a?(Array)`.

### spec/bug_break_in_block_spec.rb (Category 7)

Tests whether `break` inside a block works correctly, particularly regarding register/variable state after break.

**Scenarios (all must be present):**

1. **break inside each block, value used after**: Iterate with `each`, `break` when a condition is met, verify variables set before break retain correct values after the block. This mirrors `regalloc.rb:316-317`.

   ```
   result = nil
   [1, 2, 3, 4, 5].each do |x|
     if x == 3
       result = x
       break
     end
   end
   result.should == 3
   ```

2. **break inside each block with multiple local variables**: Use several local variables (at least 4-5) before and inside the block. After break, verify ALL of them retain correct values. The original bug was about `break` resetting `ebx` (a register), so stressing register allocation is key.

   ```
   a = 10
   b = 20
   c = 30
   found = nil
   [1, 2, 3].each do |x|
     found = x
     break if x == 2
   end
   a.should == 10
   b.should == 20
   c.should == 30
   found.should == 2
   ```

3. **break with value from block (return value of iteration)**: Some Ruby methods (`detect`, `find`) use break's return value. Test `break value` form.

4. **break inside nested iteration**: `outer.each { |x| inner.each { |y| break if condition } }` — break from the inner loop only.

5. **break inside block with method calls before and after break point**: Ensure method calls that use registers before the break don't corrupt state.

6. **Edge case: break as very first statement in block**: `[1,2,3].each { |x| break }` — break before any other work.

## Mocking Strategy

**No mocking is needed.** These specs test Ruby language constructs, not component interactions. Each spec is a self-contained Ruby program that the compiler compiles and runs. The compiler itself is implicitly the system under test.

The only "dependency" is the custom mspec helper (`rubyspec_helper.rb`), which is inlined by `run_rubyspec` during compilation. It provides the `describe/it/.should` framework.

## Invocation

### Individual spec (during development):

```bash
./run_rubyspec spec/bug_yield_in_nested_block_spec.rb
./run_rubyspec spec/bug_variable_name_collision_spec.rb
./run_rubyspec spec/bug_ternary_expression_spec.rb
./run_rubyspec spec/bug_block_given_nested_spec.rb
./run_rubyspec spec/bug_self_recursive_lambda_spec.rb
./run_rubyspec spec/bug_parser_divergence_spec.rb
./run_rubyspec spec/bug_break_in_block_spec.rb
```

Each command compiles the spec with the compiler and runs the resulting binary. Exit code is non-zero if any test fails or if compilation fails.

### All bug specs at once:

```bash
./run_rubyspec spec/bug_yield_in_nested_block_spec.rb && \
./run_rubyspec spec/bug_variable_name_collision_spec.rb && \
./run_rubyspec spec/bug_ternary_expression_spec.rb && \
./run_rubyspec spec/bug_block_given_nested_spec.rb && \
./run_rubyspec spec/bug_self_recursive_lambda_spec.rb && \
./run_rubyspec spec/bug_parser_divergence_spec.rb && \
./run_rubyspec spec/bug_break_in_block_spec.rb
```

### All specs (includes existing + new):

```bash
make spec
```

Runs `./run_rubyspec ./spec` which processes all `*_spec.rb` files. Output saved to `docs/spec.txt`.

### Validation after workaround removal:

```bash
make selftest && make selftest-c
```

Both must pass. `selftest` compiles the compiler with MRI, then runs the compiler's self-test. `selftest-c` compiles the compiler with itself, then runs the self-test again. These are the definitive validation that workaround removal didn't break anything.

## Known Pitfalls

### 1. Specs MUST use mspec format

Every spec file MUST begin with `require_relative '../rubyspec/spec_helper'` and use `describe/it/.should` blocks. Plain Ruby scripts with `puts` assertions will not work with `run_rubyspec`.

### 2. A failing spec does NOT necessarily mean the bug is confirmed

Some specs may fail to **compile** rather than failing at runtime. Track both outcomes:
- **Compilation failure** = confirmed bug (construct can't even be compiled)
- **Runtime failure** (wrong value) = confirmed bug (compiles but produces wrong result)
- **Segfault** = confirmed bug (compiles but crashes)
- **Passes** = bug is stale for that specific construct

### 3. Spec passes ≠ safe to remove workaround

A spec testing the general construct might pass, but the specific usage in the compiler source might still fail. After a spec passes, the workaround must still be removed and validated with `make selftest && make selftest-c`. The spec is a necessary but not sufficient condition.

### 4. Remove workarounds ONE AT A TIME

Never batch multiple workaround removals across categories. If selftest fails after removing a workaround, you need to know exactly which removal caused it. Within a category, individual markers can be removed independently, but each removal must be followed by `make selftest && make selftest-c`.

### 5. The `run_rubyspec` preprocessor rewrites your code

Be aware that `run_rubyspec` performs transformations before compilation:
- Instance variables `@var` are rewritten to globals `$spec_var`
- `describe(...)` and `it(...)` get parenthesized
- `require_relative` lines are stripped

Avoid using instance variables in specs (use locals instead). If you need class-level state, use class variables `@@var` or globals.

### 6. Do NOT test the rescue workaround (marker 21)

`emitter.rb:399-401` uses `block.call` because `rescue` is not supported. This is explicitly out of scope — exception support is a separate feature. Skip it.

### 7. Do NOT modify files in rubyspec/

All new specs go in `spec/`, never in `rubyspec/`. This is an inviolable project rule.

### 8. The parser divergence specs (Category 6) require special care

Marker 18 (`parser.rb:797`) describes a case where MRI and the self-hosted compiler parse differently. The spec can only detect whether the construct works when compiled. It cannot directly test parser AST output. The definitive test for parser divergence is `make selftest-c` (which uses the self-hosted parser). If the spec passes but `selftest-c` fails after removing the workaround, the parser divergence is real.

### 9. break semantics vs. register corruption

Category 7 tests `break` at the language level, but the actual bug is register corruption (`ebx` reset). A spec that tests `break` behavior might pass even if the underlying register bug exists, because the test might not stress register allocation enough. Use at least 4-5 local variables to increase register pressure.

### 10. Compilation can be slow

Each `./run_rubyspec` invocation compiles a spec from scratch (no caching). Running all 7 specs sequentially will be slow. Run them individually during development, and only run the full suite for final validation.

### 11. Do NOT create separate specs for duplicate markers

Markers 20 and 25 are the same bug (break in regalloc.rb). Markers 19 and 22 overlap (parser/with_local). Don't create duplicate spec files — one spec per root-cause category is correct.

### 12. Self-recursive lambda spec needs the ternary to work

The factorial lambda test (`n <= 1 ? 1 : n * fact.call(n-1)`) uses a ternary. If Category 3 (ternary) is a confirmed bug, rewrite the recursive lambda test to use `if/else` instead, to avoid conflating two bugs.
