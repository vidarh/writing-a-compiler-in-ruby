# Ternary Operator Bug in Self-Compiled Code

## Summary

When the self-compiled compiler compiles code containing ternary operators (`cond ? true_val : false_val`), 
the false branch may incorrectly return `false` instead of the actual `false_val` expression value.

## Discovery

Found during debugging of selftest-c failure (2025-10-19). The compiler was failing with:
```
Method missing FalseClass#get_arg
```

This occurred in `compile_class.rb` line 40:
```ruby
vtable_scope = in_eigenclass ? orig_scope : scope
```

When `in_eigenclass` was `false`, the ternary operator returned `false` instead of `scope`.

## Workaround

Replace ternary operators with if/else when values matter (not just for boolean results):

**Don't use:**
```ruby
result = condition ? true_value : false_value
```

**Use instead:**
```ruby
if condition
  result = true_value
else
  result = false_value
end
```

## Files Affected

- `compile_class.rb:40-46` - Fixed by converting ternary to if/else

## Root Cause

The ternary operator compilation likely has a bug where the false branch's return value
is not properly handled, causing it to return the literal `false` value instead of 
evaluating and returning the false_val expression.

## Test Case

A minimal test case would be:
```ruby
def test_ternary(flag)
  obj = Object.new
  result = flag ? :true_val : obj
  result
end

puts test_ternary(false).class  # Should print "Object", not "FalseClass"
```

When compiled with the self-compiled compiler, this would return `false` instead of `obj`.

## Status

**Workaround applied**: Convert ternary to if/else in affected code.
**Root cause**: NOT YET FIXED - ternary operator compilation needs investigation.
**Impact**: Medium - ternary operators should be avoided in compiler source until fixed.
