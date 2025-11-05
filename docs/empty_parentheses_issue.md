# Empty Parentheses Issue (ab083aa)

## Problem

Commit ab083aa "Fix empty parentheses to evaluate as nil in expressions" breaks selftest-c compilation with a segfault.

## Original Change

The commit added logic to distinguish empty parentheses `()` from empty arrays `[]` and empty hashes/blocks `{}`:

```ruby
elsif op.type == :rp
  # Only push :nil for empty parentheses (), not for empty arrays [] or hashes/blocks {}
  # Check ostack.first.sym: nil for (), :array for [], :hash_or_block for {}
  if lastlp && ostack.first && ostack.first.sym.nil?
    @out.value(:nil)
  elsif lastlp
    @out.value(nil)  # For empty [] and {}, push nil placeholder
  end
  @out.value(nil) if src.lasttoken and src.lasttoken[1] == COMMA
```

## Why It's Needed

Empty parentheses `()` should evaluate to `nil` in boolean expressions:
- `() && true` should parse as `[:and, :nil, :true]`
- Without this, it became `[:and, :true]` which causes compile_and to receive wrong number of arguments

This fixes RubySpec tests for empty expressions with `&&` and `and` operators.

## Why It Breaks selftest-c

The conditional `lastlp && ostack.first && ostack.first.sym.nil?` causes segfaults during self-compilation. The issue appears to be with complex conditionals involving method chains (`ostack.first.sym.nil?`).

## Attempted Fixes That Failed

1. **Storing intermediate values:**
   ```ruby
   first_op = ostack.first
   if first_op
     first_sym = first_op.sym
     if first_sym.nil?
   ```
   Result: Still segfaults

2. **Using `== nil` instead of `.nil?`:**
   ```ruby
   if first_sym == nil
   ```
   Result: Still segfaults

3. **Breaking down the entire chain:**
   - Separating all conditions into individual if statements
   - Result: Still segfaults

## Current Workaround

Reverted to simple logic:
```ruby
elsif op.type == :rp
  @out.value(nil) if lastlp
  @out.value(nil) if src.lasttoken and src.lasttoken[1] == COMMA
```

This allows selftest-c to pass but breaks the empty parentheses feature.

## Root Cause Hypothesis

The compiler has a bug with:
- Complex boolean expressions involving multiple method calls
- Method chains like `obj.method.another_method.predicate?`
- Potentially related to how method returns are handled in conditionals

## Testing Methodology

1. Checkout commit ab083aa
2. Apply simple shunting.rb fix (revert empty parentheses logic)
3. Build: `rm -f out/driver* && make compiler`
4. Test: `make selftest-c`
5. Result: PASSES

With the complex logic:
4. Test: `make selftest-c`
5. Result: SEGFAULT at __cnt: 632000 (during compilation of selftest.rb)

## Next Steps to Fix

1. **Investigate the compiler bug with method chains in conditionals:**
   - Create minimal test case that reproduces the segfault
   - Test simpler forms of the condition
   - Identify which specific pattern causes the crash

2. **Alternative approaches:**
   - Store `ostack.first.sym` in a separate data structure during parsing
   - Use a flag instead of checking `.sym.nil?`
   - Refactor to avoid the conditional entirely (different AST representation)

3. **Temporary solution:**
   - Implement empty parentheses handling at a different compilation phase
   - Add a transform pass that converts `nil` placeholders to `:nil` symbols

## Related Specs

RubySpec tests that need this feature:
- `language/and_spec.rb` - Empty expressions with `&&` operator
- `language/or_spec.rb` - Empty expressions with `||` operator
- Various fixture files that use `() && expr` patterns

## Files Affected

- `shunting.rb` (lines 100-117)
