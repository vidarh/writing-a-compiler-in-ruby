# Block Parameter Scoping Bug

## Summary
**Critical Bug**: Block parameters are not properly scoped - they're treated as method calls on Object instead of local variables.

## Test Case
```ruby
3.times { |i| puts i }
# Error: "Method missing Object#i"

h = { 1 => 2 }
h.each { |k, v| puts v }
# Error: "Method missing Object#v"
```

## Root Cause
The compiler does not recognize block parameters as local variables within the block scope. When it encounters `|i|` or `|k, v|`, it doesn't create proper local variable bindings.

## Impact on Integer Specs

**29 SEGFAULT specs** are affected - almost ALL use blocks with parameters:
- abs_spec: Uses `{}.each do |key, values|` and nested `values.each do |value|`
- times_spec: Uses `9.times { |i| }` 
- allbits/anybits/nobits: Likely use .each loops
- Most comparison specs: Likely use test iteration with blocks

**Key Finding**: Lambdas DO work inside methods (tested and confirmed). The issue is specifically block parameter scoping.

## Current Workarounds Attempted

### What Works
- ✅ Lambdas inside methods: `x = lambda { puts "hi" }; x.call` works fine
- ✅ Blocks without parameters: `5.times {}` works

### What Fails
- ❌ Block parameters: `{ |x| ... }` - x not recognized as local
- ❌ Multiple block params: `{ |k, v| ... }` - both fail
- ❌ Nested blocks with params: Double failure

## Why Top-Level Test Was Misleading
Initially tested lambdas at TOP LEVEL which is a known problem. Testing inside methods shows lambdas work fine - the real issue is block parameter scoping regardless of context.

## Files to Investigate
- Block parameter handling in parser
- Scope management for block local variables  
- Transform phase for block rewriting

## Recommendation
This is a fundamental compiler architecture issue that affects ~40% of failing specs. Cannot be worked around in rubyspec_helper - requires fixing the compiler's block parameter scoping mechanism.
