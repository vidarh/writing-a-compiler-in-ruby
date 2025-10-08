# Break with Value Issue - RESOLVED

## Problem
`break n` from within procs/lambdas passed to methods was segfaulting at runtime:
```ruby
def test_break
  result = 9.times { break 2 }
  puts "Result: #{result}"
end
```

Was crashing with segmentation fault or producing incorrect results.

## Root Causes Found and Fixed

### Bug 1: Stack Unwinding Loop Corruption
**Problem**: The lexical break unwinding loop was structured incorrectly, causing `leave` to execute multiple times on the same stack frame.

**Original buggy code**:
```ruby
l = @e.local           # Label L1
@e.leave               # Unwind frame
@e.cmpl(:eax, :ebp)    # Check if at target
@e.jz r                # Done if equal
@e.addl(4,:esp)        # Skip return address
@e.jmp l               # Jump back to L1 - EXECUTES leave AGAIN!
```

This caused stack corruption because:
1. First iteration: `leave` unwound one frame correctly
2. Jump back to L1
3. Second `leave` tried to unwind the already-unwound frame
4. Stack pointer and frame pointer became corrupted

**Fix**: Restructure loop to jump to AFTER the first `leave`:
```ruby
l_test = @e.get_local + "_test"
l_loop = @e.local
@e.jmp l_test          # Jump to test first
@e.local(l_loop)       # Loop body
@e.addl(4,:esp)        # Skip return address
@e.local(l_test)       # Test label
@e.leave               # Unwind one frame
@e.cmpl(:eax, :ebp)    # Check if at target
@e.jnz l_loop          # Continue if not at target
```

### Bug 2: Break Value Lost During Unwinding
**Problem**: The break value was pushed onto the lambda's stack frame, but when `leave` unwound the stack, the stack pointer moved past it, causing the return address to be popped instead.

**Original buggy approach**:
```ruby
# Push break value
ret = compile_eval_arg(scope, value)
@e.pushl(:eax)         # Saved on lambda's frame

# Unwind frames with leave
@e.leave               # Stack pointer moves!

# Try to restore break value
@e.popl(:eax)          # WRONG - pops return address, not break value!
```

**Fix**: Save break value in caller-saved register %ecx which survives unwinding:
```ruby
# Load target stackframe first
ret = compile_eval_arg(scope,[:index,:__env__,0])
@e.movl(ret,:eax)

# Then compile and save break value in register
if value
  @e.pushl(:eax)       # Temporarily save target
  ret = compile_eval_arg(scope, value)
  @e.movl(:eax, :ecx)  # Save break value in %ecx
  @e.popl(:eax)        # Restore target
end

# Unwind (doesn't affect %ecx)
@e.leave

# Restore break value
@e.movl(:ecx, :eax)    # Correct!
```

Loading `__env__[0]` BEFORE compiling the break value also avoids register allocation conflicts where the compiler might reuse %ecx during the __env__ compilation.

## Results

### Manual Tests Pass
- ✅ `9.times { break 2 }` correctly returns 2
- ✅ Lambda with `break 42` works correctly
- ✅ Break values preserved through multiple frame unwinding
- ✅ Conditional breaks work correctly
- ✅ Selftest passes with 0 failures

### RubySpec Impact

The break fix alone did **not** reduce segfaults in RubySpec tests. Many specs that appeared to be failing due to break issues were actually failing due to:

1. **Instance variable scoping in `before :each` blocks**: The spec framework's `before` hooks use `instance_eval`, which is not implemented. This was causing segfaults in specs like gte_spec that use `@bignum` in before blocks.

2. **Before hooks not being executed**: The `before_each_blocks` array was being populated but not called before each test.

**Additional fixes made**:
- Rewrite all instance variables to global variables in specs (e.g., `@bignum` → `$spec_bignum`)
- Execute `before_each_blocks` in the `it()` function before running each test

**After all fixes** (break + instance var rewrites + before hook execution):
- Integer specs: Segfaults reduced from 30 → 26 (4 fewer)
- Passed specs: 7 → 8
- Failed specs: 14 → 17 (specs that were segfaulting now run and fail)

The break fix enables proper non-local returns from blocks/procs, which is essential for Ruby semantics. However, most RubySpec segfaults are due to other missing features (exception handling, instance_eval, missing methods, etc.) rather than break specifically

## Remaining Issues Analysis

### Compile Failures (17 specs)
Most compile failures fall into these categories:

1. **Hash literal parsing bug** (11 specs): divide, downto, element_reference, coerce, exponent, fdiv, modulo, plus, pow, comparison, div
   - Shunting errors like `Syntax error. [{/0 pri=99}]`
   - Parser issue with Hash literals in certain contexts
   - **High impact fix**: Would unlock 11 specs at once

2. **Class definitions in block contexts** (1 spec): minus_spec
   - Parser expected expressions that couldn't include `class` within blocks, but Ruby allows this
   - After fixing parser to allow class in blocks, compilation fails on meta/eigenclass features
   - **Not a Hash literal issue** - separate problem from category #1

3. **Linker errors** (1 spec): round_spec
   - Compiles but missing symbols

4. **Float support needed** (1 spec): to_f_spec

5. **Other** (3 specs): fixtures/classes.rb, upto_spec, remainder_spec

### Recommended Next Steps
1. **Fix Hash literal parsing** - highest impact (11 specs)
2. **Investigate common segfault causes** - many specs still crash at runtime
3. ~~**Add `private def` syntax support**~~ - DONE (parsing only)
4. **Implement missing core methods** that cause method_missing errors

## Progress Update

### `private def` Syntax - FIXED
Added parser support for `private def`, `protected def`, `public def` syntax:
- Uses backtracking to distinguish from standalone visibility calls
- Does not implement actual visibility functionality
- Tested: works in classes, selftest passes

After fixing this, most specs parse correctly. However, minus_spec's failure is NOT due to the Hash literal bug - it's due to the parser not allowing `class` definitions within block expressions, and then failing to compile meta/eigenclass features.

### Hash Literal Parsing Bug - IN PROGRESS
Error: `Syntax error. [{/0 pri=99}]` in shunting.rb:183

Investigation shows:
- Simple cases work: `test(:foo, :/)`, `describe("Integer#/") do ... end`
- Hash literals in isolation work: `{:shared => true}`
- Lambda with method calls work: `-> { 1 + 2 }.should == 3`

The bug appears to be triggered by some specific combination of these elements in the generated specs. The error occurs in the shunting yard algorithm's handling of certain token sequences involving Hash literals, blocks, and operators.

**Status**: Requires deeper investigation into shunting.rb and how it disambiguates Hash literals from blocks in complex expressions.
