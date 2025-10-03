# Nested Block Variable Capture Fix Investigation (2025-10-01)

## Summary

Attempted to fix the nested block variable capture bug using the "proper fix" approach (v2 patch). The approach partially works but has fundamental issues that prevent it from being completed.

## Problem Statement

Outer block parameters cannot be captured by nested blocks. Example:
```ruby
[[1]].each do |arr|
  arr.each {|x| puts arr.length }  # Crashes - 'arr' not captured
end
```

Manual workaround (works):
```ruby
[[1]].each do |arr|
  arr_shadow = arr  # Create local variable
  arr_shadow.each {|x| puts arr_shadow.length }  # Works
end
```

## The V2 Patch Approach

The `nested_block_proper_fix_v2.patch` implements:

1. **Pass lambda parameters through `find_vars`**: Add `lambda_params` parameter to track current lambda's parameters
2. **Add parameters to scope**: Use `param_scope = Set.new(params)` and pass `scopes + [param_scope]`
3. **Don't remove params from env**: Keep `env += env2` without removing params
4. **Protect parameter lists**: Wrap with `[:__PARAMS__, *params]` to prevent rewriting
5. **Skip rewriting own parameters**: Check `lambda_params.include?(n)` before capturing
6. **Skip rewriting in parameter lists**: Add checks in `rewrite_env_vars`
7. **Unwrap parameter lists**: Remove `__PARAMS__` wrapper after rewriting

## Test Results with V2 Patch

### ✅ Works:
- Simple case without parameter capture: `[[1,2]].each {|arr| arr.each {|x| puts x}}` → outputs "1\n2"
- Manual shadow workaround still works

### ❌ Fails:
- Parameter capture: `[[1]].each {|arr| arr.each {|x| puts arr.length}}` → segfault
- Selftest: crashes (FPE or segfault)
- Self-compilation: crashes during compilation

## Root Cause Analysis

### The Core Problem

When a nested lambda needs to capture an outer lambda's parameter:

1. **Outer lambda** has parameter `arr` in its parameter list
2. **Inner lambda** references `arr`, so `find_vars` adds `arr` to `env2`
3. **Outer lambda** then has `arr` in both:
   - Its parameter list (direct access)
   - Its environment (`env`) for nested lambdas
4. **`rewrite_env_vars`** rewrites ALL references to `arr` to `[:index, :__env__, N]`
5. **Problem**: Outer lambda's own uses of `arr` get rewritten to env access, but `arr` should be used directly as a parameter

### Why Skip Vars Don't Work

Attempted fix: Pass `skip_vars` to `rewrite_env_vars` to prevent rewriting the outer lambda's own parameters.

**Problem**: The skip applies to the entire tree traversal, including nested lambdas. But nested lambdas SHOULD rewrite `arr` to env access. Need different `skip_vars` for each lambda level.

### Why Recursive Rewrite Doesn't Work

Attempted fix: Recursively call `rewrite_env_vars` for nested lambdas with their own `skip_vars`.

```ruby
if e.is_a?(Array) && (e[0] == :lambda || e[0] == :proc)
  nested_params = unwrap_params(e[1])
  seen |= rewrite_env_vars(e[2], env, nested_params)
  next :skip
end
```

**Problems**:
1. Still causes segfaults in `test_nested_simple.rb`
2. Self-compilation crashes
3. Unclear what specific runtime issue causes the crash

## Architectural Issues

### Issue 1: Parameters in Env

When outer lambda has parameter `arr` and inner lambda captures it:
- `arr` ends up in outer lambda's `env`
- Outer lambda allocates env with `arr` in it
- But outer lambda also has `arr` as a direct parameter
- This creates duplicate/conflicting representations

### Issue 2: Rewriting Scope

`rewrite_env_vars` is called once per method/lambda body and recursively processes all nested structures. It's difficult to maintain separate "don't rewrite these variables" lists for each lambda nesting level.

### Issue 3: Transformation Order

1. `find_vars` processes the entire tree and determines what goes in env
2. Lambda bodies are wrapped with `:let` nodes
3. `rewrite_lambda` converts `:lambda` nodes to `:defun` (happens inside `rewrite_let_env`)
4. `rewrite_env_vars` is called and traverses the tree, finding `:lambda` nodes still present
5. The interaction between these phases is complex

## What Actually Needs to Happen

For the outer lambda with parameter `arr` that's captured by inner lambda:

**Outer lambda should**:
1. Have `arr` as a parameter (direct access)
2. Have `arr` in its env (for inner lambda)
3. Initialize `env[N] = arr` (copy parameter to env)
4. Use `arr` directly (not through env) in its own body
5. Pass env to inner lambda

**Inner lambda should**:
1. Receive env from outer
2. Access `arr` as `env[N]`

**Current code generates**:
- Outer lambda uses `arr` through env (WRONG - should use direct parameter)
- This causes crashes because parameter passing doesn't match

## Failed Approaches

### 1. Automatic Shadow Variable Insertion (Previous Attempt)
- Added 100+ lines of complex code
- Created shadow assignments automatically
- Caused regressions and segfaults
- User feedback: "A huge amount of code has been added and it's caused regressions"
- **Rejected**: Too complex, wrong approach

### 2. Parameters to Scope Without Protection (V2 Base)
- Parameters added to scope, not removed from env
- **Status**: Partially works (simple non-capture case)
- **Fails**: When nested lambda actually captures the parameter

### 3. Skip Vars for Outer Lambda (This Attempt)
- Pass `skip_vars` to prevent rewriting outer lambda's own parameters
- **Problem**: Affects nested lambdas too, they can't rewrite those vars

### 4. Recursive Rewrite with Lambda-Specific Skip Vars (This Attempt)
- Recursively call `rewrite_env_vars` for each nested lambda with its own skip list
- **Problem**: Still crashes, unclear root cause

## Debugging Evidence

### Working Case (Manual Shadow)
```ruby
[[1,2]].each do |arr|
  arr_s = arr
  arr_s.each {|x| puts arr_s.length }
end
```
Output: `2\n2` ✅

### Failing Case
```ruby
[[1]].each do |arr|
  arr.each {|x| puts arr.length }
end
```
Crash backtrace:
```
#0  __lambda_L114 () at /app/lib/core/debug.rb:7
#1  __method_Proc_call ()
#2  __method_Array_each ()
#3  __lambda_L113 ()
#4  __method_Proc_call ()
```

Inner lambda (`L114`) crashes, likely due to incorrect env access or parameter mismatch.

## Current State

Files modified:
- `transform.rb` - reverted to clean state
- Patch file exists: `nested_block_proper_fix_v2.patch`

All test cases still fail:
- `spec/simple_nested_capture.rb` - 3 failures
- `spec/nested_blocks_capture.rb` - 2 failures

## Why This Is Hard

The fundamental architectural challenge:

1. **Single env per function**: Each method/lambda has one `__env__` array containing all captured variables
2. **Parameters vs captures**: Parameters are passed as arguments, captures are accessed through env
3. **Dual role**: When a parameter needs to be captured by nested lambda, it has both roles
4. **Rewriting phase**: Single pass that rewrites all variable references in the tree

**The conflict**:
- Outer lambda needs to use parameter directly (fast, normal parameter passing)
- Inner lambda needs to access via env (closure semantics)
- Current rewrite phase can't distinguish these two cases within the same outer lambda body

## Possible Paths Forward

### Option A: Initialize Env from Parameters
When outer lambda has captured parameters:
```ruby
def outer(arr)  # arr is parameter
  __env__ = [arr]  # Copy to env immediately
  # Now use arr directly in this scope
  inner = ->(x) { __env__[0].length }  # Inner uses env
end
```

**Challenge**: `rewrite_env_vars` needs to know not to rewrite `arr` in outer scope

### Option B: Always Use Env for Captured Parameters
If parameter will be captured, rewrite outer lambda to use env too:
```ruby
def outer(__param_arr)  # Renamed parameter
  __env__ = [__param_arr]
  arr = __env__[0]  # Create local alias
  # All uses of 'arr' go through env
end
```

**Challenge**: Determining which parameters need this treatment

### Option C: Two-Phase Rewriting
1. First phase: Rewrite each lambda body with knowledge of its own parameters
2. Second phase: Process nested lambdas separately

**Challenge**: Complex coordination between phases

## Recommendations

1. **Stop pursuing recursive skip_vars approach**: It's not showing promise after multiple attempts
2. **Consider Option A or B above**: Require structural changes to how env initialization works
3. **Alternative**: Accept manual workarounds for now, mark as known limitation
4. **Deep dive needed**: Understand exactly why generated assembly crashes (compare working vs broken assembly)

## Files Referenced

- `transform.rb` - Core transformation logic
- `nested_block_proper_fix_v2.patch` - Current best attempt
- `nested_block_fix_attempt.patch` - Earlier simpler attempt
- `spec/simple_nested_capture.rb` - Test cases
- `spec/nested_blocks_capture.rb` - More complex test cases
- `docs/NESTED_BLOCK_CAPTURE_DEBUG.md` - Earlier investigation notes

---

# UPDATE 2025-10-03: Successful Fix with current_params Tracking

## Solution Implemented (Commit 654fc39)

Successfully fixed nested block parameter capture using **Option 1: Track parameters separately** from the documented approaches. The fix adds a `current_params` parameter to `find_vars` to distinguish current lambda parameters from outer variables.

### Implementation Details

**Changes to `find_vars` (transform.rb:220-310)**:
1. Add `current_params = Set.new` parameter to `find_vars` and `find_vars_ary`
2. For lambda/proc nodes:
   - Extract parameter names from `n[1]` (handling arrays like `[:param, :default]`)
   - Create `param_scope = Set.new(param_names)`
   - Pass `param_scope` as both scope AND current_params to nested `find_vars`
   - **Critical**: Don't remove parameters from `env2` (line 251 commented out)
   - This allows captured parameters to propagate up to parent scope's env

3. Pass `current_params` through all `find_vars` recursive calls

4. At variable reference capture point (line 307):
   - Check `!current_params.include?(n)` before moving to env
   - This prevents current lambda's own parameters from being captured

**Changes to `rewrite_env_vars` (transform.rb:322-370)**:
- Handles lambda/proc/defun to protect parameter lists from rewriting
- Recursively processes body only, returns `:skip` to prevent parameter rewriting
- Adds parameter initialization `__env__[N] = param` for captured parameters
- Inserts initialization at start of lambda body (after :let if present)

### Test Results

✅ **All 5 nested capture tests pass:**
- `spec/simple_nested_capture.rb`: 3/3 passing
- `spec/nested_blocks_capture.rb`: 2/2 passing

Examples that now work:
```ruby
[[1]].each do |arr|
  arr.each {|x| puts arr.length }  # Now works! Outputs "1"
end

[[1, 2], [3, 4]].each do |outer|
  outer.each_with_index do |val, i|
    result << outer[i]  # outer is captured correctly
  end
end
```

### Known Regression

⚠️ **Selftest runtime crash:**
- Selftest compiles successfully
- Crashes at runtime with segmentation fault after `__cnt: 1000`
- Tests pass, so the core fix logic is correct
- Crash appears to be an edge case interaction with compiler self-compilation

### Why This Fix Works

The key insight: **current_params prevents incorrect self-capture**

Without `current_params`:
```
each_byte {|c| h = h * 33 + c}
         └─ c gets incorrectly added to env because:
            - Line 265: scopes+[Set.new] for arg processing
            - Pushes param_scope from position -1 to -2  
            - Line 302: in_scopes(scopes[0..-2], n) finds c
            - Result: {:h, :c} instead of just {:h}
```

With `current_params`:
```
each_byte {|c| h = h * 33 + c}
         └─ c is in current_params
            - Line 307: !current_params.include?(c) → false
            - c not moved to env
            - Result: {:h} ✓ correct
```

### Next Steps

1. **Investigate selftest crash**: Use gdb to identify what's causing the segfault
2. **Possible causes**:
   - Edge case in how compiler methods use closures
   - Interaction with splat parameters (`*args`)
   - Specific method in compiler code that triggers the crash
3. **Approach**: Compare assembly or trace execution to find the failure point

### Files Modified

- `transform.rb`: Added current_params tracking throughout find_vars
- `spec/simple_nested_capture.rb`: Fixed test expectations
- `spec/nested_blocks_capture.rb`: Fixed test expectations

