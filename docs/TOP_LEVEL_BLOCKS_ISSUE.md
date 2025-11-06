# Known Limitation: Top-Level Blocks/Lambdas Broken

## Status
KNOWN LIMITATION - Long-standing documented issue

## Re-discovered
Session 46 - 2025-11-05 (wasted significant time)

## Severity
**LIMITATION** - Only affects top-level code, NOT code inside methods

## Symptoms

Any code that uses lambda or block parameters fails with "undefined method" error:

```ruby
# All of these fail with "undefined method 'i'"
[1, 2, 3].each { |i| puts i }
[1, 2, 3].each do |i| puts i end
lambda { |i| puts i }.call(42)
f = lambda { |i| puts i }

# For loops fail because they're transformed to .each
for i in [1, 2, 3]
  puts i
end
```

Error message: `Unhandled exception: undefined method 'i' for Object`

## Root Cause

The lambda/block parameter is not being recognized as a variable. Instead, it's being treated as a method call on the receiver object.

This suggests the scope/variable lookup for lambda parameters is broken in the code generation phase.

## Key Discovery

**Blocks/lambdas work FINE inside methods!** The issue is ONLY at top level.

```ruby
# TOP LEVEL - BROKEN
[1,2,3].each { |i| puts i }  # ✗ undefined method 'i'

# INSIDE METHOD - WORKS
def test
  [1,2,3].each { |i| puts i }  # ✓ Works perfectly!
end
```

## Impact

**AT TOP LEVEL ONLY:**
- For loops: Fail
- Lambdas with parameters: Fail
- Blocks with parameters: Fail

**INSIDE METHODS: Everything works fine!**

## Why This Causes Time Waste

1. **RubySpecs wrap all code in methods** → Don't hit this issue
2. **Test files often use top-level code** → Hit this issue
3. **Leads to false bug reports** → Waste time investigating

**SOLUTION: Always wrap test code in methods!**

## Test Cases

All of these fail when compiled and run:

```ruby
# 1. Simple array each
[1, 2, 3].each { |i| puts i }

# 2. Hash each
{"a" => 1}.each { |k, v| puts k }

# 3. Lambda
lambda { |i| puts i }.call(42)

# 4. For loop (any form)
for i in [1, 2, 3]
  puts i
end

# 5. For loop with destructuring
for i, j in [[1, 2], [3, 4]]
  puts i
end
```

## Investigation Needed

1. **Where are lambda parameters supposed to be registered?**
   - Check compile_class.rb for lambda compilation
   - Check how the scope is set up for lambda bodies

2. **How are parameters passed to lambdas?**
   - Check the calling convention
   - Check if parameters are being stored in the right place

3. **Why does variable lookup fail?**
   - The error "undefined method 'i'" suggests `:i` is being looked up as a method
   - This means the scope doesn't have `i` registered as a local variable
   - Check Scope class and how lambda scopes are created

## Related Code

- `compile_class.rb` - Lambda/proc compilation
- `transform.rb:710-724` - For loop transformation (creates lambdas)
- `scope.rb` - Scope and variable tracking
- `compiler.rb` - Main compilation logic

## Workaround

None. Avoid using:
- Lambdas with parameters
- Blocks with parameters
- For loops (any form)
- Iterator methods like `.each`, `.map`, `.select` with blocks

## Priority

**CRITICAL** - This affects core Ruby functionality and blocks using many language features.

## Session 46 Note

This bug was discovered when attempting to:
1. Add `loop` method (blocked on yield issues)
2. Fix for loop bare splat support (discovered for loops completely broken)
3. Investigate why for loops fail (discovered ALL lambda/block parameters broken)

The investigation revealed that the issue is much deeper than just for loops - it's a fundamental problem with how lambda/block parameters are compiled.
