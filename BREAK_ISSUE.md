# Break with Value Issue

## Problem
`break n` from within procs/lambdas passed to methods segfaults at runtime:
```ruby
def test_break
  result = 9.times { break 2 }
  puts "Result: #{result}"
end
```

Crashes with segmentation fault at address 0x00000013 (value 19).

## Investigation Summary

### What Works
- Parse: `parse_break` correctly parses `break 2` as `[:break, 2]`
- Transform: `rewrite_lambda` correctly places break in lambda body
- Compile: `compile_break` generates assembly for lexical break mechanism
- Assembly: Generated code correctly loads `__env__` from 3rd parameter and implements lexical break

### The Assembly
Lambda `__lambda_L131` for `{ break 2 }`:
```asm
movl    $5, %eax           # Load value (2)
pushl   %eax               # Save on stack
movl    16(%ebp), %eax     # Load __env__ (3rd param at offset 16)
movl    (%eax), %eax       # Dereference to get __env__[0]
# ... lexical break mechanism
```

### Root Cause
Runtime segfault suggests:
1. Corrupted function pointer in Proc object (jumping to 0x13 = 19)
2. Issue with stack manipulation during lexical break
3. Possible problem with how `__env__` is set up or passed

### Key Findings
- Top-level procs (like `9.times { break 2 }` at file scope) are NOT transformed by `rewrite_lambda` - this is a known bug, not the issue to fix
- Procs inside methods ARE transformed correctly
- The lexical break code path (no break_label) is executed
- The break value is saved/restored correctly in the assembly

### Next Steps
1. Debug why address 0x13 is being jumped to as a function pointer
2. Check Proc object construction - is `@addr` field correct?
3. Verify stack state after lexical break - is something corrupted?
4. Test simpler case with explicit __env__ access to isolate the issue
