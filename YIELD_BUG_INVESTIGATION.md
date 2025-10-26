# Critical Bug: User-Defined Methods with Yield

## Summary

Calling user-defined methods that contain `yield` causes a segfault during execution.

## Status

**BLOCKER** for exception handling in spec framework - we need `it()` method to yield and wrap in rescue.

## Test Cases

### ✅ Works
```ruby
# Define but don't call
def with_yield
  yield
end
puts "ok"
```

### ✅ Works  
```ruby
# Use lib/core methods with yield
a = [1,2,3]
a.find { |x| x > 2 }  # Array#find uses yield internally
```

### ❌ Crashes
```ruby
# Define AND call
def with_yield
  yield
end

with_yield do
  puts "block"
end
# Segfault at 0x565c4130 (invalid address - jumping to data, not code)
```

## Root Cause

When a user-defined method with yield is called:
1. The block Proc object is created
2. The block's code address is stored in the Proc
3. **BUG**: The address is wrong - points to data instead of code
4. When yield calls the block, it jumps to invalid address
5. Segfault

## Why Array#find Works

Array#find is compiled as part of lib/core during compiler build. User-defined methods are compiled differently when compiling user programs. The bug is in how user program blocks are compiled.

## Files Involved

- `compiler.rb`: compile_block, compile_yield methods
- `compile_calls.rb`: compile_callm (handles block passing)
- `compile_class.rb`: compile_defm (methods get __closure__ parameter)

## Next Steps

1. Find where block lambda addresses are generated for user code
2. Compare to how lib/core blocks are compiled
3. Fix the address generation
4. Test with simple yield case
5. Then add rescue back

## Impact

Blocks ALL three bug fixes:
1. ❌ Can't fix yield+rescue (yield itself doesn't work)
2. ❌ Can't test instance vars in blocks (blocks don't work) 
3. ❌ Can't test &block methods (related to yield)

**This is the root bug that must be fixed first.**
