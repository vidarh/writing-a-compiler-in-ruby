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
param_scope = Set.new(n[1] || [])
vars, env2= find_vars(n[2], scopes + [param_scope],env, freq, true)
```

**Result:** Infinite recursion/stack overflow during compilation

**Why it fails:** The `find_vars` function (lines 298-306) processes symbols and if they're found in outer scopes AND we're in a lambda, it tries to move them to env (line 305: `env << n`). But parameters shouldn't be in env at the lambda level - they're actual parameters. This creates a contradiction that causes the recursion.

### Attempt 2: Don't Remove Parameters from env2
Commented out the line that removes parameters from environment:
```ruby
# env2  -= n[1] if n[1]
```

**Result:** Compiler fails to compile itself

### Attempt 3: Add Parameters to env Temporarily
Pass parameters as part of env when processing the body:
```ruby
params = n[1] || []
env_with_params = env + params
vars, env2= find_vars(n[2], scopes + [Set.new], env_with_params, freq, true)
```

**Result:** Compiler compiles but segfaults when running selftest

### Attempt 4: Auto-insert Shadowing Assignments
Detect nested lambdas and automatically insert `p = p` assignments for all parameters:
```ruby
if has_nested_lambda && params.any? && n[2]
  shadow_assigns = params.map { |p| E[:assign, p, p] }
  n[2] = E[n[2].position, :do, *shadow_assigns, n[2]]
end
```

**Result:** Causes stack overflow if parameters are also added to scope (needed for RHS of assignment to resolve)

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

## Key Insights for Proper Fix

### Why Simple Approaches Don't Work

The problem is that parameters exist in a special space:
1. They're NOT local variables (they're function arguments)
2. They're NOT in any scope that `find_vars` can see
3. But they NEED to be capturable by nested lambdas

When `find_vars` encounters a symbol (lines 298-306 in transform.rb):
- It checks if the symbol is in an outer scope (`in_scopes(scopes[0..-2], n)`)
- If yes AND `in_lambda` is true, it moves it to `env` (line 305)
- Parameters are never in scopes, so they're never moved to env

### The Correct Approach: Shadowing/Aliasing

The manual workarounds show the solution:
1. Create a local variable with the same (or different) name as the parameter
2. Assign the parameter value to it: `arr = arr` (or `arr_alias = arr`)
3. This local variable IS in scope and CAN be captured
4. **Critical:** ALL references to the parameter in the outer block must use the aliased version, not just those in nested blocks (to avoid complex lifetime analysis)

For example:
```ruby
[[1,2]].each do |arr|
  arr.each {|x| puts x}
end
```

Should be transformed to:
```ruby
[[1,2]].each do |arr|
  arr = arr  # Shadow assignment
  arr.each {|x| puts x}
end
```

Now `arr` is a local variable that can be captured by the nested block.

### Implementation Challenges

1. **Detecting which parameters need shadowing**: Need to detect if there are nested lambdas that might reference the parameter
2. **Inserting shadow assignments**: Must happen BEFORE find_vars processes the body
3. **Making parameters visible**: The RHS of `arr = arr` needs to resolve to the parameter
   - Can't add to scope (causes recursion)
   - Can't add to env (parameters aren't captured variables)
   - Need special handling in find_vars for RHS of shadow assignments
4. **Rewriting references**: All uses of the parameter must become uses of the shadowed local

### Critical Discovery: :proc Nodes Not Being Rewritten

**Root Cause:** `:proc` and `:lambda` nodes outside of method bodies are never processed by `rewrite_lambda`.

- `rewrite_lambda` is only called within `rewrite_let_env` on method bodies (transform.rb:436)
- `rewrite_let_env` uses `depth_first(:defm)` which only processes method definitions
- Procs created outside methods (e.g., blocks passed to `.each` at top level) remain as `:proc` nodes
- The compiler has no `compile_proc` method - it expects all procs to be rewritten to lambda definitions
- This causes "undefined method `compile_proc`" errors when compiling code with top-level blocks

**Testing Results:**
- `arr = arr` in a simple block: WORKS
- `arr.each` nested block without shadow: WORKS
- `arr = arr` followed by nested block: FAILS (compile error - :proc not rewritten)

**Attempted Fix:** Adding `rewrite_lambda(exp)` at end of `preprocess` causes linker error "undefined reference to `__env__`", suggesting double-rewriting creates issues.

**ATTEMPTED FIX:** Created `rewrite_lambda_outside_methods` function that:
- Does `exp.depth_first` to walk entire tree
- Skips `:sexp` and `:defm` nodes (methods handled by rewrite_let_env)
- Rewrites `:lambda` and `:proc` nodes outside methods
- Called before `rewrite_let_env` in preprocess

**Result:** Causes linker error "undefined reference to `__env__`"

**Why it fails:** Procs rewritten outside methods reference `__env__` but top-level code doesn't have `__env__` allocated. Only method bodies get `__env__` via `rewrite_let_env`. This is a fundamental architectural issue - lambda rewrites assume they're inside a method context.

### Current Status (After :proc Rewriting Fix)

**Test Results:**
- Test 1 (simple nested each): "1\n2" (missing final newline, but better than before)
- Test 2 (parameter reference in nested block): Empty output (arr.length not working)
- Test 3 (each_with_index parameter capture): Empty output (i not captured)

**Manual shadow assignment (`arr = arr`):** Still produces no output in nested blocks

### Key Discovery: Self-Assignment Doesn't Shadow Parameters

User insight: `arr = arr` won't create a new variable if `arr` already exists as a parameter! In Ruby, assignment to an existing variable just assigns to that variable - it doesn't create a shadowed version.

**Solution requires either:**
1. **Unique shadow name**: `arr_shadow = arr` then use `arr_shadow` everywhere
   - ✅ **CONFIRMED WORKING** - `test_shadow_in_method.rb` compiles and runs correctly!
   - The shadow variable IS captured by nested blocks
   - The captured variable IS rewritten to use the environment
2. **Compiler transformation**: Automatically detect parameters used in nested blocks and insert proper shadowing

**Architectural Blocker:** Top-level procs (outside methods) aren't being rewritten at all, causing "undefined method `compile_proc`" errors when they're encountered.

### Summary of Findings

1. **Root cause**: Parameters are removed from `env` (transform.rb:247) so nested lambdas can't capture them
2. **Why parameters are removed**: They're function arguments, not captured variables
3. **Manual workarounds exist**: Three places in compiler use pattern `alias=param` to force capture
4. **Simple fix attempts fail**: Adding parameters to scope causes infinite recursion
5. **Shadow assignment insight**: `param = param` doesn't work because param already exists
6. **:proc rewriting issue**: Top-level procs need special handling for `__env__` allocation

**Manual Workaround (PROVEN TO WORK):**
Users can work around this bug by manually creating shadow variables with unique names:
```ruby
def foo
  [[1]].each do |arr|
    arr_shadow = arr  # Create shadow with unique name
    arr_shadow.each {|x| puts arr_shadow.length }  # Use shadow everywhere
  end
end
```

**Why Automatic Fix Is Complex:**
Attempted automatic fixes failed because:
1. Adding parameters to scope causes them to be rewritten to `[:index, :__env__, N]`
2. Function parameters must be simple symbols, not expressions
3. Would need to:
   - Insert shadow assignments
   - Rewrite ALL references to parameters (not just in nested blocks)
   - Handle parameter initialization from the actual parameters

This is essentially what the 3 existing manual workarounds do.

**Recommendation:**
- Keep using manual workarounds for now (pattern: `shadow=param`)
- Document the limitation
- A proper fix requires careful AST transformation to insert shadows and rewrite all references

## Further Attempts (2025-10-01)

### Attempt: Add Parameters to Scope (Proper Approach)

The "proper" fix is to get parameters into `env` so `rewrite_env_vars` naturally rewrites them.

**Change made:**
```ruby
elsif n[0] == :lambda || n[0] == :proc
  params = n[1] || []
  # Add parameters to scope so nested lambdas can see them
  param_scope = Set.new(params)
  vars, env2= find_vars(n[2], scopes + [param_scope],env, freq, true)

  # Clean out proc/lambda arguments from the %s(let ..)
  vars  -= params
  # Don't remove from env2 - parameters that ended up there are needed by nested lambdas
  env += env2
```

**Problem encountered:**
- Parameters in `env` get rewritten to `[:index, :__env__, N]` by `rewrite_env_vars`
- This happens in parameter lists themselves, not just in bodies
- Results in error: `Internal error: Arg.name must be Symbol; '[:index, :__env__, 2]'`

**Attempted fix:**
Added protection to `rewrite_env_vars` to skip lambda/proc parameter lists:
```ruby
def rewrite_env_vars(exp, env, skip_params = false)
  # Skip lambda/proc parameter lists - parameters stay as symbols
  if skip_params && e.is_a?(Array) && (e[0] == :lambda || e[0] == :proc)
    # Manually process: rewrite body but not params
    if e.size > 2 && e[2]
      seen = rewrite_env_vars(e[2], env, true) || seen
    end
    next :skip
  end
  # ... rest of function
```

Called with: `rewrite_env_vars(body, aenv, true)` from `rewrite_let_env`

**Result:**
- Simple nested blocks compiled but produced no output (should output "1")
- **CRITICAL REGRESSION:** Self-compilation completely broken
  - `./out/driver test/selftest.rb` produced 0-byte output file
  - `make selftest-c` fails
- Approach abandoned due to regression

**Why it failed:**
The compiled compiler segfaults or produces empty output, suggesting the transformation breaks something fundamental in the compiler's own code. The compiler uses nested blocks extensively, and the change to how parameters are handled likely breaks one of these critical code paths.

### Attempt: Automatic Shadow Variable Insertion

Earlier attempt (documented in previous sections) to automatically insert shadow assignments like `autoenv#{param} = param` and rewrite all references.

**Problems:**
1. Shadow variable names starting with `_` treated as special by `is_special_name?`
2. Method names incorrectly rewritten (needed special handling for `:callm`, `:call`)
3. Caused segfaults at runtime
4. Added 100+ lines of complex code

**Result:** Abandoned as "hacky workaround" with too many edge cases and unclear runtime failures.

## Debugging Strategy

To debug transformations at a fine-grained level, you can build a test script that:

1. **Run compilation steps incrementally** (equivalent to `--norequire` to avoid loading everything)
2. **Dump AST before transformation**
3. **Run the specific transformation being tested**
4. **Dump AST after transformation**
5. **Compare the two ASTs** to see exactly what changed

Example approach:
```ruby
require './parser'
require './scanner'
require './transform'
require 'stringio'
require 'pp'

code = File.read('test_minimal_nest.rb')
io = StringIO.new(code)
scanner = Scanner.new(io)
parser = Parser.new(scanner)
ast = parser.parse

puts "=== BEFORE TRANSFORMATION ==="
pp ast

# Run specific transformation
compiler = Compiler.new(...)
compiler.some_transform_step(ast)

puts "=== AFTER TRANSFORMATION ==="
pp ast
```

This allows directly observing:
- Whether parameters are being added to scopes correctly
- Whether they're appearing in `env` sets
- Whether `rewrite_env_vars` is rewriting them
- Whether parameter lists are being protected from rewriting
- Exact structure of generated `:let` nodes and shadow assignments

Much more effective than trying to debug from assembly output or runtime crashes.

## Current Status (2025-10-02 - Partial Fix, Core Challenge Identified)

### Changes Committed

**Commit 1 (fa0c561):** Initial fix attempt - REVERTED
- Added parameters to scope in find_vars
- Added parameter initialization in rewrite_env_vars
- Tests passed but selftest crashed with FPE

**Commit 2 (7a000ab):** Partial infrastructure fix - COMMITTED
- lib/set.rb: Add Set.new(enum) support
- transform.rb: Protect lambda/proc parameter lists from rewriting
- selftest passes, but nested block tests still fail
- selftest-c still crashes (regression)

### Core Challenge Discovered

**The fundamental problem with adding parameters to scope:**

When parameters are added to a lambda's scope, nested expression processing incorrectly treats them as outer variables:

1. Lambda has `params = [:c]`, creates `param_scope = Set.new([:c])`
2. Calls `find_vars(body, scopes + [param_scope], ...)`
3. Body processing encounters `:callm` with arguments (line 265)
4. Argument processing adds empty scope: `scopes + [Set.new]`
5. Now scopes = `[...outer..., param_scope, Set.new]`
6. Symbol lookup checks `scopes[0..-2]` (all except current)
7. Finds `:c` in `param_scope` at position [-2]
8. Incorrectly treats `:c` as outer variable, adds to env

**Result:** Parameters get captured even when they shouldn't be.

**Test failure:** `find_vars should identify all variables in a proc`
- Expected: `[[], #<Set: {:h}>]`
- Got: `[[], #<Set: {:h, :c}>]`
- Parameter `:c` incorrectly added to env

### Why This is Hard

The scope hierarchy is designed for LOCAL VARIABLES:
- First assignment creates variable in current scope (position -1)
- Later references in nested lambdas find it in outer scopes (position -2+)
- Outer scope variables are moved to env for capture

But PARAMETERS are never "assigned" - they appear directly in the signature. Adding them to the current scope makes them look like outer variables to any child expression that adds a new scope (which is common - argument evaluation, nested calls, etc.).

### Possible Solutions to Explore

**Option 1: Track parameters separately from scopes**
- Pass lambda parameters as separate argument through find_vars
- Check against parameter list before checking scopes
- Only capture if found in ACTUAL outer scopes, not current lambda's params

**Option 2: Use negative depth markers**
- Mark parameter scopes differently (e.g., with a wrapper)
- Update in_scopes to skip parameter scopes when they're at position -1
- Only treat as capturable when found in truly outer lambdas

**Option 3: Two-pass approach**
- First pass: identify which params are REFERENCED by nested lambdas
- Second pass: add only those params to scope and env
- More complex but avoids false positives

**Option 4: Post-process to add initialization**
- Keep current approach (don't add params to scope)
- After transformation, scan for lambdas that reference outer lambda params
- Insert initialization code at that point
- Challenge: identifying which references need initialization

**Option 5: Accept manual workarounds**
- Document that users must manually shadow: `arr_shadow = arr`
- Three places in compiler already use this pattern
- Simplest but not ideal for users

## Previous Status (2025-10-02 - Working Fix with Regression)

### Fix Implementation

**Successfully implemented nested block parameter capture!**

**Changes made:**

1. **transform.rb line 243-252:** Add parameters to scope in `find_vars`
   - Parameters added to `param_scope` so nested lambdas can find them
   - Don't remove params from `env2` (line 251 commented out)

2. **transform.rb line 325-366:** Special handling in `rewrite_env_vars`
   - Process lambda/proc/defun bodies without rewriting parameter lists
   - Add initialization for captured parameters: `__env__[N] = param`
   - Insert initialization AFTER rewriting body (so param symbol isn't rewritten)
   - Return `:skip` to prevent double-processing

**How it works:**

1. `find_vars` adds lambda parameters to scope
2. Nested lambdas reference these parameters, adding them to `env2`
3. `env2` propagates up to outer lambda
4. `rewrite_env_vars` detects which params are in env
5. Rewrites body first (all param uses become `__env__[N]`)
6. Then inserts `__env__[N] = param` at start of body
7. Both outer and nested lambdas use `__env__[N]` for shared state

**Test Results:**

✅ **Nested block tests PASS:**
- Simple nested each: outputs correct values
- Parameter reference in nested block: outputs correct values
- each_with_index parameter capture: outputs correct values
- Only failures are missing final newlines (cosmetic)

❌ **Selftest FAILS:**
- Compiles successfully
- Runs briefly (shows __cnt: 1000, __cnt: 2000)
- Crashes with Floating Point Exception
- Indicates bug in specific code path

### Remaining Issue

The fix works for the target use case but breaks selfcompilation. Need to identify which code in the compiler itself triggers the crash.

**Possible causes:**
1. Edge case in parameter initialization logic
2. Issue with empty parameter lists
3. Problem with parameter extraction from tuples
4. Interaction with existing workarounds

**Next steps:**
1. Create minimal test case that triggers the crash
2. Add debug output to identify crash location
3. Fix the specific edge case
4. Verify selftest passes

## Previous Status (2025-10-01 - Latest Fix Attempt)

### Key Understanding

**Critical architectural requirement:** When an outer lambda's parameter is captured by a nested lambda, BOTH lambdas must access it via `__env__`. They cannot have independent copies.

**Why both must use env:**
- If outer lambda uses parameter directly: `arr` (parameter)
- And nested lambda uses env: `__env__[N]`
- Then they're TWO DIFFERENT VARIABLES
- Updates to one won't be seen by the other
- This breaks closure semantics

**Correct architecture:**
1. Outer lambda has `arr` as parameter (symbol in signature)
2. Outer lambda has `arr` in its env set
3. Outer lambda initializes: `__env__[N] = arr` (copy param to env)
4. ALL references to `arr` in outer lambda use `__env__[N]`
5. Nested lambda inherits env and uses `__env__[N]`

### Latest Fix Implementation

**Changes made in transform.rb:**

1. **Line 243-246:** Add parameters to scope so nested lambdas can find them
   ```ruby
   param_scope = Set.new(n[1] || [])
   vars, env2= find_vars(n[2], scopes + [param_scope],env, freq, true)
   ```

2. **Line 252:** Don't remove params from env2 (commented out `env2 -= n[1]`)
   - Parameters captured by nested lambdas must stay in env

3. **Line 326-334:** Protect parameter lists from rewriting in `rewrite_env_vars`
   ```ruby
   if e.is_a?(Array) && (e[0] == :lambda || e[0] == :proc || e[0] == :defun)
     body_index = e[0] == :defun ? 3 : 2
     if e[body_index]
       seen |= rewrite_env_vars(e[body_index], env)
     end
     next :skip  # Don't let depth_first process children (would rewrite params)
   end
   ```
   - Manually recurse into body only
   - Skip parameter list to keep params as symbols

**Result of changes:**
- ✅ Parameters now stay as symbols in signatures: `(arr default nil)`
- ✅ Body correctly uses env access: `(callm (index __env__ 1) each ...)`
- ❌ **Missing initialization:** No `(assign (index __env__ 1) arr)` statement

### Remaining Problem

**Issue:** Parameter initialization is missing for lambda/proc nodes.

- `rewrite_let_env` (lines 427-430) adds initialization for `:defm` methods
- But `:lambda`/`:proc` nodes are converted to `:defun` by `rewrite_lambda` (line 62)
- These `:defun` nodes are NOT processed by `rewrite_let_env`
- So no initialization code is added

**Why this matters:**
- Parameter `arr` exists as function parameter
- Body references `__env__[1]`
- But `__env__[1]` is never initialized from `arr`
- Results in garbage value/crash

**Order of transformations:**
1. `rewrite_let_env` processes `:defm` nodes
2. Calls `find_vars` to determine env set
3. Calls `rewrite_env_vars` to rewrite references
4. Calls `rewrite_lambda` to convert `:lambda` to `:defun`
5. Lambda `:defun` nodes created AFTER env processing

**Next steps:**
- Need to add parameter initialization in `rewrite_lambda` for params that are in env
- Challenge: `rewrite_lambda` doesn't know which params are in env
- May need to pass env info to `rewrite_lambda` or restructure transformation order

**Working state:** Manual workarounds only (3 instances in codebase using `alias=param` pattern)

## Detailed Debugging with AST Dumps (2025-10-01)

Using the incremental debugging strategy, I created test scripts to dump ASTs and trace execution:

### Key Discovery: The Scope Hierarchy Problem

**Working case (manual shadow):**
```ruby
[[1]].each do |arr|
  arr_shadow = arr  # Shadow assignment
  arr_shadow.each {|x| puts arr_shadow.length }
end
```

AST analysis shows:
- `arr_shadow` is a local variable (from assignment)
- When nested lambda references `arr_shadow`, `find_vars` finds it in outer scope
- `find_vars` moves it to `env`: `Environment needed: {:arr_shadow}`
- `rewrite_env_vars` rewrites references to `[:index, :__env__, N]`
- ✅ Works correctly

**Broken case (parameter):**
```ruby
[[1]].each do |arr|
  arr.each {|x| puts arr.length }
end
```

AST analysis shows:
- `arr` is a parameter, NOT in any scope
- When nested lambda references `arr`, `find_vars` doesn't find it in scopes
- NOT moved to env: `Environment needed: {}`
- References stay as `:arr` symbol
- ❌ Fails - parameter not captured

### Attempt: Add Parameters to Scope

**Change:**
```ruby
params = n[1] || []
param_scope = Set.new(params)
vars, env2= find_vars(n[2], scopes + [param_scope],env, freq, true)
# Don't remove params from env2
env += env2
```

**Problem discovered through tracing:**

When `find_vars` processes lambda with parameter `x`:
1. Creates `param_scope = Set.new([:x])`
2. Calls `find_vars(body, scopes + [param_scope], ...)`
3. Body processing encounters child nodes, recurses with `scopes + [Set.new]`
4. Now scopes = `[...outer..., param_scope, Set.new]`
5. Symbol lookup checks `scopes[0..-2]` (all except current)
6. Finds `x` in `param_scope` at position [-2]
7. Treats `x` as **outer scope variable**, moves to env
8. ❌ Parameter of CURRENT lambda incorrectly added to env

**Result:**
- Simple case `[1,2,3].each {|x| puts x}`: `env = {:x}` (WRONG!)
- Parameter `x` gets rewritten to `[:index, :__env__, N]`
- Function signature broken: `Arg.name must be Symbol` error
- Even after fixing `rewrite_env_vars` to skip lambda params, runtime crashes

**Why it fails:**
Parameters must be in `scopes[-1]` (current scope), but ANY recursion in `find_vars` pushes them to `scopes[-2]` (outer scope). The scope hierarchy makes it impossible to distinguish "parameter of current lambda" from "parameter of outer lambda" using the current architecture.

### Root Cause

The `find_vars` function uses a simple rule (lines 301-308):
```ruby
elsif n.is_a?(Symbol)
  sc = in_scopes(scopes[0..-2],n)  # Check outer scopes
  if sc.size == 0
    push_var(scopes,env,n) if in_assign  # New variable
  elsif in_lambda
    sc.first.delete(n)
    env << n  # Move outer scope var to env
  end
end
```

This works for local variables because:
- First reference (in assignment): creates variable in current scope
- Later references in nested lambda: found in outer scope, moved to env

But parameters are never "assigned" in the lambda body, so they're never added to the current scope. Adding them manually to a scope makes them look like outer scope variables to all child processing.

**Attempted fix to `rewrite_env_vars`:**
- Skip lambda/proc nodes entirely (let them be processed separately)
- This prevented parameter rewriting errors
- But caused runtime crashes (FPE/segfault)
- Self-compilation broken (segfault)

**Why rewrite fix failed:**
Unknown - requires deeper investigation. Possibly related to how lambdas are transformed to `:defun` nodes and processed separately, or env allocation/initialization issues.

### Conclusion

The "proper" fix (parameters in env) is blocked by fundamental architecture:
- Can't distinguish "current lambda's parameters" from "outer lambda's parameters" using scope hierarchy
- Would need to track parameter ownership per-scope or use a different lookup mechanism
- All attempted workarounds cause regressions in self-compilation

Manual shadowing remains the only working approach.
