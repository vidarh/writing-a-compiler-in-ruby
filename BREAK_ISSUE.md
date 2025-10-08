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
All test cases now pass:
- ✅ `9.times { break 2 }` correctly returns 2
- ✅ Lambda with `break 42` works correctly
- ✅ Break values preserved through multiple frame unwinding
- ✅ Conditional breaks work correctly

The fix enables proper non-local returns from blocks/procs, essential for Ruby semantics and RubySpec compatibility
