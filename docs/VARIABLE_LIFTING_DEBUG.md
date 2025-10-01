# Variable Lifting Bug Investigation

## Problem Statement
Variables referenced in blocks (lambdas, procs, or blocks passed to methods) are not being correctly identified by `find_vars`, which means they don't get properly captured in the environment.

## Symptoms
- Workarounds needed in `shunting.rb:133-134` - just referencing `ostack` and `opstate`
- Workaround in `compile_calls.rb:19` - referencing `scope`
- Workaround in `lib/core/array.rb` sort method - referencing `pivot` in block
- Test failures when outer variables are used in blocks without workarounds

## Test Cases Created
File: `spec/variable_lifting.rb`
- Test 1: Captures outer variable in block passed to method (e.g., `pivot` in each block)
- Test 2: Captures outer variable in partition block
- Test 3: Captures multiple outer variables in block
- Test 4: Captures variable in nested blocks

All 4 tests fail with "Assembly failed"

## Key Code Locations
- `transform.rb:231` - `find_vars` method definition
- `transform.rb:242-250` - `:lambda`/`:proc` handling - passes `in_lambda=true`
- `transform.rb:252-270` - `:callm` handling in find_vars - passes `in_lambda` unchanged
- `transform.rb:271-287` - `:call` handling in find_vars - passes `in_lambda` unchanged
- `transform.rb:294-302` - Symbol handling - only captures to env if `in_lambda` is true

## Root Cause Analysis

### The Bug
When `find_vars` processes a Symbol (variable reference) at lines 294-302:
```ruby
elsif n.is_a?(Symbol)
  sc = in_scopes(scopes[0..-2],n)
  freq[n] += 1 if !is_special_name?(n)
  if sc.size == 0
    push_var(scopes,env,n) if in_assign && !is_special_name?(n)
  elsif in_lambda
    sc.first.delete(n)
    env << n  # <-- Only happens if in_lambda is true!
  end
```

Variables are only added to `env` (for closure capture) when `in_lambda` is true.

### The Problem
- `in_lambda` is set to `true` only for `:lambda` and `:proc` nodes (line 243)
- Blocks passed to methods (n[4] in `:callm`, n[3] in `:call`) are processed with `in_lambda` unchanged
- This means variables referenced in blocks passed to methods are NOT captured in the environment

### Example
```ruby
pivot = 10
[1, 5, 15].each do |e|
  e < pivot  # 'pivot' should be captured but isn't
end
```

When processing the block body, `pivot` is found as a Symbol, but since `in_lambda=false`, it's not added to the environment for capture.

## Test Results - Initial Run
PASSED (2/4):
- Test 1: Single variable (pivot) in block - WORKS ✓
- Test 2: Single variable in partition block - WORKS ✓

FAILED (2/4):
- Test 3: Multiple variables (x, y) in block - Empty output, likely crash
- Test 4: Nested blocks with outer variable - Empty output, likely crash

## Key Finding
Single variable capture WORKS! This means the basic mechanism is functioning. The bug only manifests with:
1. Multiple outer variables captured in one block
2. Nested blocks

## Revised Hypothesis
The original hypothesis about `in_lambda` was INCORRECT - blocks ARE being processed correctly as `:proc` nodes and single variables ARE being captured.

The issue must be:
1. Something about handling multiple variables in the environment
2. Something about nested block/scope handling
3. A bug in how the environment array is built or accessed

Need to investigate:
- How environment arrays are constructed when multiple variables are captured
- How nested blocks handle environment chaining

## Critical Discovery - IF Statement Effect

Created test files to compare parse trees:
- `test_single_var.rb`: `pivot` used directly in block - pivot NOT captured
- `test_single_if.rb`: `pivot` used in IF inside block - pivot IS captured!
- `test_multi_var.rb`: x and y used directly - only y captured, x not captured

**Preprocessed Trees Show:**

1. **With IF (works):** pivot → `__env__[1]`
   ```
   (let (__env__ __tmp_proc)  # pivot NOT in let
   (assign (index __env__ 1) (sexp 21))  # assigned to env
   ```

2. **Without IF (breaks):** pivot → direct reference
   ```
   (let (pivot __env__ __tmp_proc)  # pivot IN let
   (assign pivot (sexp 21))  # assigned as local
   ```

3. **Multiple vars (breaks):** x stays local, y goes to env
   ```
   (let (x __env__ __tmp_proc)  # only x in let, y missing!
   (assign x (sexp 11))  # x as local
   (assign (index __env__ 1) (sexp 21))  # y to env
   ```

## Root Cause
The bug is NOT about whether variables are found, but about WHICH variables get moved to the environment vs staying as locals. Variables need to be captured in `env` but some are being left in the local scope (the `let` statement).

The IF statement somehow triggers proper environment capture, while direct usage does not.

Next: Examine how find_vars handles control flow (if/while/etc) vs simple expressions.

## Investigation of Fix Attempt #1
Tried removing the extra `Set.new` scope added when processing call arguments (lines 259, 277).

**Result:** Broke existing tests (selftest-c fails).

**Conclusion:** The extra scope is necessary for correctness. Removing it breaks existing functionality.

## Current Understanding
The extra scope added for processing arguments prevents variables from being captured in the environment when they're used deeply nested in call arguments.

When a variable is in an IF condition, it's processed without extra scopes, so capture works.
When a variable is in nested call arguments, multiple extra scopes are added, somehow preventing proper capture.

The bug manifests as:
1. First variable referenced (x) stays in local scope (let)
2. Second variable referenced (y) goes to environment
3. This inconsistency causes runtime errors

Need to understand WHY the extra scope prevents capture and find a way to fix it without breaking existing tests.

## Simplified Test Case
Created `test_two_vars_simple.rb`:
```ruby
def test
  x = 5
  y = 10
  f = lambda { puts x + y }
  f.call
end
```

**Preprocessed tree shows:**
```
(let (y f __env__ __tmp_proc)  # y in let, x not in let!
  (assign (index __env__ 1) (sexp 11))  # x → __env__[1]
  (assign y (sexp 21))  # y → local variable
  ...
  lambda body: (callm (index __env__ 1) + (y))  # x from env, y direct reference
```

**The bug**: y is accessed directly in the lambda but it's not in the lambda's scope - it's in the outer function's scope. This causes crash/error.

## Why Does This Happen?
In find_vars (lines 299-302), when a symbol is found in an outer scope while `in_lambda=true`:
```ruby
sc.first.delete(n)  # Delete from outer scope
env << n  # Add to env
```

The variable SHOULD be deleted from the outer scope and added to env. But somehow:
- x gets properly moved to env
- y stays in the outer scope

This suggests that when y is encountered, either:
1. `sc.first.delete(n)` fails to delete it, OR
2. y is added back to the scope after being deleted, OR
3. y is processed in a context where it's added to scope but the deletion doesn't happen

Need to trace the exact order of operations.

## BREAKTHROUGH: The Bug is Call-Related!

Created `test_simple_no_std.rb`:
```ruby
def test
  x = 5
  y = 10
  f = lambda { x + y }  # NO puts
  f.call
end
```

**Result: WORKS CORRECTLY!**
```
(let (f __env__ __tmp_proc)  # Neither x nor y in let!
  (assign (index __env__ 1) (sexp 11))  # x → __env__[1]
  (assign (index __env__ 2) (sexp 21))  # y → __env__[2]
  ...
  lambda body: (callm (index __env__ 1) + ((index __env__ 2)))  # Both from __env__!
```

**With puts (`lambda { puts x + y }`)**: y stays in outer scope (BROKEN)
**Without puts (`lambda { x + y }`)**: both x and y go to __env__ (WORKS)

## Root Cause
The bug is triggered by having a `:call` node (like `puts`) as the top-level expression in the lambda body. When the lambda body is a direct expression (`x + y`), it works. When it's wrapped in a call (`puts (x + y)`), the variable capture breaks.

The issue is in how find_vars processes `:call` nodes' arguments with `scopes+[Set.new]` (line 277). This extra scope interferes with the variable deletion/env capture mechanism.

## Deep Investigation Results

### Key Findings:
1. **The wrapping is intentional**: Lines 267 and 284 wrap blocks in arrays `[n[4]]` and `[n[3]]`
2. **:proc handler IS triggered**: Line 242's condition DOES match and line 243 executes
3. **in_lambda=true IS passed**: The recursive call explicitly passes `true` for in_lambda
4. **But variables are STILL processed with in_lambda=false**: Despite all of the above!

### The Mystery:
- Traced execution confirms line 243 runs: `find_vars(n[2], scopes + [Set.new],env, freq, true)`
- Yet when `:x` is processed, in_lambda=false
- The lambda body SHOULD contain `:x` and it SHOULD be processed with in_lambda=true
- But it's not happening

### Working vs Broken:
- **`lambda { x + y }` (no puts)**: Works! Both x and y captured to __env__
- **`lambda { puts x + y }` (with puts)**: Broken! Only some vars captured

### Hypothesis:
The issue may be related to:
1. How the parse tree is structured when `puts` (a :call) is involved
2. The order of processing when :call contains expressions with variables
3. Some interaction between the wrapped array and the recursion that breaks the in_lambda propagation

This bug requires more investigation to fully understand the control flow and why in_lambda isn't propagating correctly through the recursive calls.

## CONFIRMED ROOT CAUSE

### Test Case Comparison

**Code WITHOUT puts (WORKS):**
```ruby
lambda { x + y }
```
Result: Both x and y captured to __env__

**Code WITH puts (BROKEN):**
```ruby
lambda { puts x + y }
```
Result: Only x captured to __env__, y stays as local variable

### The Bug Mechanism

When find_vars processes the lambda body:

**Working case:** `[[:callm, :x, :+, [:y]]]`
- Processes `:callm` node
- x is in arguments, gets processed with extra scope
- y is in arguments, gets processed with extra scope
- Both get captured because in_lambda=true propagates correctly

**Broken case:** `[[:call, :puts, [[:callm, :x, :+, [:y]]]]]`
- Processes `:call` node (line 271-287)
- Arguments `[[:callm, :x, :+, [:y]]]` processed at line 277
- Extra scope added: `scopes+[Set.new]`
- x is deeply nested, y is at outer level of the expression
- **Hypothesis**: The extra scope from `:call` argument processing causes y to be seen as "already in scope" when it's processed, preventing its capture to env

The bug is in how the scope nesting interacts with the in_scopes check at line 295-302 in transform.rb.

## Deep Investigation Summary

After extensive tracing, confirmed:
1. find_vars IS called and DOES process the :lambda node (via iteration at line 234)
2. The lambda body IS processed with in_lambda=true (line 243)
3. Both x and y are encountered during processing

The issue must be in the SEQUENCING of when variables are added to scopes vs when they're checked for capture.

**Working theory**: When processing `[:call, :puts, [[:callm, :x, :+, [:y]]]]`:
- The `:call` handler adds an extra scope for arguments (line 277)
- Variable order of encounter/processing causes y to be added to an intermediate scope before the lambda's in_lambda=true processing reaches it
- This makes y appear as "already in scope" when the capture check happens, preventing its move to __env__

**Next steps for fixing**:
1. Trace the exact sequence: when is y added to which scope?
2. Why doesn't x have the same problem?
3. Test if removing or modifying the extra scope in :call argument handling fixes the issue

The bug is subtle and involves timing/ordering of scope modifications during AST traversal.

## Fix Attempts

### Attempt 1: Remove extra scope for `:call` arguments only
**Change:** Modified line 279 in transform.rb to use `scopes` instead of `scopes+[Set.new]` when `in_lambda=true`

**Result:**
- ✓ selftest and selftest-c pass
- ✗ Variable lifting tests still fail (2/4 tests failing)

**Conclusion:** Partial fix addresses `:call` but doesn't fix `:callm` which is needed for expressions like `x + y`

### Attempt 2: Remove extra scope for both `:call` and `:callm` arguments
**Change:** Modified both lines 261 and 279 to conditionally remove extra scope when `in_lambda=true`

**Result:**
- ✗ selftest-c fails with floating point exception (crash in `Array::sort_by`)
- ✗ Variable lifting tests still fail (2/4 tests failing)
- ✗ Causes infinite recursion/stack overflow when compiling some test cases

**Conclusion:** This approach breaks existing functionality and causes compiler crashes. The extra scope for `:callm` arguments appears to be necessary for correct operation, possibly to prevent block parameters from being incorrectly captured.

### Why the Fix Doesn't Work

The extra scope serves multiple purposes:
1. Isolates call arguments from the current scope
2. Prevents block parameters from being seen as outer-scope variables
3. Some workarounds in the codebase (e.g., `lib/core/array.rb:937-938` in `sort`) depend on current behavior

Removing the extra scope causes cascading issues:
- Block parameters may be incorrectly captured to environment
- Variables may conflict between different nesting levels
- Compiler itself enters infinite loops when processing certain patterns

The fix requires a more nuanced approach that:
- Preserves the extra scope's isolation properties
- Still allows proper variable capture in lambdas
- Doesn't break existing workarounds and code patterns

This is a deep architectural issue in how scopes and variable capture interact.

##  PARTIAL FIX APPLIED

### The Fix (transform.rb:279)
Changed from:
```ruby
vars2, env2 = find_vars(n2, scopes+[Set.new], env, freq, in_lambda)
```

To:
```ruby
vars2, env2 = find_vars([n2], scopes+[Set.new], env, freq, in_lambda)
```

This wraps the argument `n2` in an array `[n2]` before passing to `find_vars`.

### Why It Works
When a `:call` node's arguments contain a `:callm` node (e.g., `puts x + y`), passing `n2` unwrapped caused `find_vars` to iterate through the array elements:
- `[:callm, :x, :+, [:y]]` was processed element by element
- `:callm`, `:x`, and `:+` were treated as bare symbols
- `:y` in the array `[:y]` was never seen

By wrapping in `[n2]`, the `:callm` node is recognized and processed correctly via the `:callm` handler.

### Test Results
With this fix:
- ✓ 3 out of 4 variable lifting tests pass
- ✓ `lambda { puts x + y }` works correctly
- ✓ selftest passes
- ✓ selftest-c passes

### Remaining Issue
One test still fails: blocks with local variable assignments inside them and multiple outer variables.

**Failing test:** `[1,2,3].each do |n| sum = n + x + y; puts sum end`

**Problem:** When a block has a local assignment inside it and references multiple outer variables in nested `:callm` operations, the FIRST variable in the chain stays as a local variable instead of being captured.

**Parse tree shows:**
```
let (x __env__ __tmp_proc)  # x incorrectly in let
Lambda body: (callm n + (x))  # x referenced directly, not from __env__
```

This suggests the issue is with nested `:callm` nodes where the receiver of an inner `:callm` contains an outer variable. The `:callm` handler at line 259 still adds an extra scope for arguments, and removing this scope breaks selftest-c.

**Further investigation needed:** The fix may require distinguishing between:
1. Arguments that are literal values (need scope isolation)
2. Arguments that are variable references (need capture)
3. Block parameters vs outer variables (need different treatment)

## COMPLETE FIX APPLIED

### Additional Fix (transform.rb:254-255, 275-276)
The partial fix addressed `:call` arguments but not nested `:callm` nodes used as receivers.

**Problem:** When processing `n + x + y`, which becomes `[:callm, [:callm, :n, :+, [:x]], :+, [:y]]`:
- The inner `:callm` node `[:callm, :n, :+, [:x]]` appears as the RECEIVER of the outer `:callm`
- It was passed unwrapped to `find_vars(n[1], ...)` at line 253
- This caused element-by-element iteration: `:callm`, `:n`, `:+`, `[:x]`
- Variable `x` was never seen during lambda processing

**Solution:** Conditionally wrap receivers before passing to `find_vars`:
```ruby
receiver = n[1].is_a?(Array) ? [n[1]] : n[1]
vars, env = find_vars(receiver, scopes, env, freq, in_lambda)
```

Applied to both `:callm` (line 254-255) and `:call` (line 275-276) handlers.

### Test Results
With both fixes:
- ✓ All 4 variable lifting tests pass
- ✓ All 83 RSpec tests pass
- ✓ `lambda { puts x + y }` works
- ✓ `[1,2,3].each do |n| sum = n + x + y; puts sum end` works
- ✓ Nested `:callm` operations correctly capture all variables
- ✓ selftest passes
- ✓ selftest-c passes

### Fix Complete
The variable lifting bug is now fully resolved. All test cases pass and the compiler successfully self-hosts.
