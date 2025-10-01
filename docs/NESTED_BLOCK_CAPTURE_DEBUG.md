# Nested Block Variable Capture Bug Investigation

## Problem Statement

Block parameters from outer blocks/lambdas are not correctly captured when referenced in nested blocks. This causes incorrect values or crashes.

## Symptoms

```ruby
[[1]].each do |arr|
  arr.each {|x| puts arr.length }  # Crashes - arr not captured
end
```

Expected output: `1`
Actual output: Empty (crash)

## Test Cases

Created in `spec/simple_nested_capture.rb` and `spec/nested_blocks_capture.rb`:
- Simple nested each - parameter used in nested block
- Parameter reference in nested block (e.g., `arr.length`)
- Nested each_with_index with outer parameter reference

All tests fail with empty output or wrong values.

## Root Cause Analysis

### Current Behavior

When processing a lambda/proc with parameters (lines 242-250 in transform.rb):

```ruby
vars, env2= find_vars(n[2], scopes + [Set.new],env, freq, true)
vars  -= n[1] if n[1]  # Remove parameters from vars list
env2  -= n[1] if n[1]  # Remove parameters from environment
env += env2
```

Parameters are explicitly removed from both `vars` (local variables) and `env2` (environment captures). This means:
1. Parameters are NOT in the environment of the outer lambda
2. Nested lambdas CANNOT capture them

### Parse Tree Evidence

For code like:
```ruby
[[1]].each do |arr|
  f = lambda { puts arr.length }
  f.call
end
```

The nested lambda `__lambda_L1` references `arr` directly:
```
(defun "__lambda_L1" (self __closure__ __env__) 
  (let ()
    (call puts ((callm arr length)))
  )
)
```

But `arr` is a parameter of the outer lambda `__lambda_L0`, not `__lambda_L1`. It should be:
```
(callm (index __env__ N) length)
```

### Why Parameters Are Removed

Parameters are removed from `env` (line 247) because they're function parameters, not captured variables. They're passed as arguments to the lambda function.

But this prevents nested lambdas from capturing them!

## Attempted Fixes

### Attempt 1: Add Parameters to Scope
Added parameters to the new scope before processing lambda body:
```ruby
param_scope = Set.new
param_scope.merge(n[1]) if n[1]
vars, env2= find_vars(n[2], scopes + [param_scope],env, freq, true)
```

**Result:** Infinite recursion/stack overflow during compilation

### Attempt 2: Don't Remove Parameters from env2
Commented out the line that removes parameters from environment:
```ruby
# env2  -= n[1] if n[1]
```

**Result:** Compiler fails to compile itself

## The Workarounds

Three workarounds exist that force capture by creating aliases:

1. `transform.rb:86` - `bug=e` in `rewrite_strconst`
2. `transform.rb:331` - `eary=e` in `rewrite_env_vars`  
3. `transform.rb:567` - `ex=e` in attr_* handler

These all follow the pattern:
```ruby
aliased_var = original_var
original_var.each do |item|
  # use aliased_var here
end
```

By creating an alias, the variable is "referenced" and gets captured.

## Next Steps for Investigation

1. Understand why adding parameters to scope causes infinite recursion
2. Investigate if parameters should be added to environment but handled specially
3. Check if there's a difference between block parameters and regular variables in how they should be captured
4. Consider if `rewrite_env_vars` needs to handle parameters differently

The fix likely requires parameters to be:
- Available in the scope during find_vars (so nested lambdas can find them)
- Added to nested lambda environments when referenced
- But NOT added to the outer lambda's vars list (since they're parameters)
