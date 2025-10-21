# Nested let() and LocalVarScope Stack Offset Bug

**Status**: BUG CONFIRMED - Test case created, solution pending
**Created**: 2025-10-21
**Priority**: HIGH - Blocks eigenclass implementation

## Summary

The `let()` helper and `LocalVarScope` implementation has a critical bug when nesting `let()` calls. The stack offset calculation in `LocalVarScope.get_arg()` does not correctly account for the stack space allocated by nested scopes, causing variable corruption.

## Reproduction

**Test Case**: `test_nested_let_minimal.rb`

```ruby
def test_basic
  %s(let (outer) (
    (assign outer 42)
    (let (inner) (
      (assign inner 99)
      (printf "Outer from inner scope: %d\n" outer)
      # BUG: prints "99" instead of "42"
    ))
  ))
end
```

**Output**:
```
Outer assigned: 42
Inner assigned: 99
Outer from inner scope: 99    <-- BUG: should be 42
```

## Root Cause Analysis

### Stack Layout Issue

When `let(scope, :var1)` is called, it:
1. Creates a `LocalVarScope` with `@locals = {var1: 1}`
2. Calls `@e.with_stack(3)` which does `subl(12, %esp)` (allocates 12 bytes)
3. Stores var1 at offset 1: `-8(%ebp)`

When a nested `let(outer_scope, :var2)` is called inside:
1. Creates another `LocalVarScope` with `@locals = {var2: 1}`, `@next = outer_scope`
2. Calls `@e.with_stack(3)` which does ANOTHER `subl(12, %esp)`
3. Stores var2 at offset 1: `-8(%ebp)` (SAME OFFSET!)

### Offset Calculation Bug

In `LocalVarScope.get_arg()` (localvarscope.rb:28):

```ruby
def get_arg(a)
  return [:lvar, @locals[a] + (rest? ? 1 : 0) + @next.lvaroffset] if @locals.include?(a)
  return @next.get_arg(a) if @next
  # ...
end
```

For the inner scope accessing `outer`:
- `@locals` doesn't have `outer`, so calls `@next.get_arg(:outer)`
- Outer LocalVarScope returns `[:lvar, 1 + 0 + function.lvaroffset]`
- But this assumes a SINGLE stack frame with contiguous allocation
- In reality, there are TWO separate `with_stack()` frames!

### Stack Frame Reality

```
Actual stack after nested let():

High addresses
  [function's stack frame]
  -4(%ebp): saved %ebx
  -8(%ebp): outer (var1, offset 1 in first with_stack)
  -12(%ebp): padding
  --- First with_stack(3) boundary ---
  -16(%ebp): inner (var2, offset 1 in second with_stack)  <-- OVERLAP!
  -20(%ebp): padding
  -24(%ebp): padding
  --- Second with_stack(3) boundary ---
Low addresses (current %esp)
```

**The bug**: When inner scope references `outer`, it calculates `-8(%ebp)`, which is correct. But when it assigns to `inner`, it ALSO uses `-8(%ebp)` because its local offset is also 1!

## Why Eigenclass Needs This

The eigenclass implementation (Session 26, WORK_STATUS.md) requires nested `let()`:

```ruby
# Outer let: evaluate expr and save to __eigenclass_obj
let(scope, :__eigenclass_obj) do |outer_scope|
  compile_eval_arg(outer_scope, [:assign, :__eigenclass_obj, expr])

  # Inner let: create eigenclass and assign to :self
  let(outer_scope, :self) do |lscope|
    compile_eval_arg(lscope, [:assign, :self, create_eigenclass(...)])
    # Need to access BOTH :self and :__eigenclass_obj here
  end
end
```

This pattern fails because the inner `let()` corrupts the outer variables.

## Impact

**Current Impact**:
- Any code using nested `let()` blocks will have variable corruption
- Variables in outer scopes get overwritten by inner scope variables
- Can cause crashes, wrong values, or segfaults

**Blocked Work**:
- Eigenclass implementation (Session 26, shelved due to this bug)
- Any complex compilation patterns that need multiple local variables
- `def self.method` syntax (uses eigenclasses)

## Proposed Solution: Approach A (Accumulate Offsets)

**Key Insight**: `LocalVarScope` needs to track the CUMULATIVE stack allocation of all nested LocalVarScopes.

### Changes Required

1. **Add stack size tracking to LocalVarScope**:
```ruby
class LocalVarScope < Scope
  attr_reader :stack_size  # NEW: Track our stack allocation

  def initialize(locals, next_scope, eigenclass_scope = false)
    @next = next_scope
    @locals = locals
    @eigenclass_scope = eigenclass_scope
    @stack_size = locals.size + 2  # Match the "s = vars.size + 2" in let()
  end

  def lvaroffset
    # Return the TOTAL offset: our allocation + next scope's offset
    offset = @stack_size + (rest? ? 1 : 0)
    offset += @next.lvaroffset if @next
    offset
  end
end
```

2. **Update get_arg() to use cumulative offsets**:
```ruby
def get_arg(a)
  a = a.to_sym
  if @locals.include?(a)
    # Our local variable: use index directly + rest adjustment
    return [:lvar, @locals[a] + (rest? ? 1 : 0)]
  end

  # Variable in outer scope: delegate but ADD our stack size
  if @next
    outer_arg = @next.get_arg(a)
    if outer_arg && outer_arg[0] == :lvar
      # Adjust the offset by our stack allocation
      return [:lvar, outer_arg[1] + @stack_size]
    end
    return outer_arg
  end

  return [:addr, a]
end
```

### How This Fixes It

With the fix:
- Outer LocalVarScope: `outer` at offset 1
- Inner LocalVarScope: `inner` at offset 1 (local), but accessing `outer`:
  - Calls `@next.get_arg(:outer)` → `[:lvar, 1]`
  - Adds `@stack_size` (3) → `[:lvar, 4]`
  - Now `outer` is at offset 4, `inner` at offset 1 - NO OVERLAP!

### Testing the Fix

After implementing:
1. Run `test_nested_let_minimal.rb` - should print "42" not "99"
2. Run `test_nested_let.rb` - all tests should pass
3. Run `make selftest` - no regressions
4. Retry eigenclass implementation from Session 26

## Alternative Approaches Considered

### Approach B: Single Allocation (REJECTED)

**Idea**: Detect nested `let()` and extend the existing LocalVarScope instead of creating a new one.

**Why Rejected**: Variable shadowing. If outer and inner scopes have same variable name:
```ruby
let(scope, :x) do
  x = 10
  let(outer, :x) do
    x = 20  # Should NOT modify outer x
  end
  # x should still be 10
end
```

### Approach C: Rewrite let() to pre-calculate (FUTURE)

**Idea**: Change `let()` to scan the block for nested `let()` calls and allocate all stack space upfront.

**Why Not Now**:
- Much more complex
- Requires analyzing the block before executing
- Approach A is simpler and sufficient

## Implementation Plan

1. ✅ Create test cases demonstrating the bug
2. ⏳ Implement Approach A (accumulate offsets)
3. ⏳ Verify tests pass
4. ⏳ Run selftest to check for regressions
5. ⏳ Document the fix
6. ⏳ Retry eigenclass implementation

## Files Involved

- `localvarscope.rb` - Core bug location
- `compiler.rb:643-664` - The `let()` helper
- `emitter.rb:334-359` - `with_stack()` and `with_local()`
- `test_nested_let_minimal.rb` - Minimal reproduction
- `test_nested_let.rb` - Comprehensive test suite
- `compile_class.rb:94-154` - Eigenclass (blocked by this bug)

## References

- **WORK_STATUS.md** Session 26: Eigenclass implementation shelved due to this bug
- **WORK_STATUS.md** Session 25: Initial eigenclass attempt, discovered LocalVarScope nesting issue
- **compiler.rb:649-656**: Comments about compiler bugs in `let()` itself
