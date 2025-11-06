# Control Flow as Expressions - Next Steps

## Current State (After Session 46)

### What Works ✅
- Control flow keywords work as expression values in expression contexts
  ```ruby
  result = if true; 42; end     # ✓ Works
  x = while i < 10; i += 1; break i; end  # ✓ Works
  ```
- Break values return correctly from loops
- Unless compilation works

### What Doesn't Work ❌
- Control flow structures in ANY expression context at statement level:
  ```ruby
  # Method chaining
  if true; 42; end.to_s         # ✗ Parse error

  # Arithmetic
  (if true; 5; end) + 10        # ✗ Parse error

  # Array literals
  [if true; 1; end, 2]          # ✗ Parse error

  # Method arguments
  puts(if true; "yes"; end)     # ✗ Parse error

  # Hash literals
  { key: if true; "val"; end }  # ✗ Parse error
  ```

## The Problem

Control flow keywords (`if`, `while`, `unless`, `until`, `for`, `begin`) are parsed in TWO places:

1. **In `parse_defexp`** (parser.rb line 484) - For statement-level control flow
2. **In the shunting yard** (shunting.rb lines 191-202) - For expression-level control flow

This dual parsing causes issues:
- At statement level, control structures are parsed by `parse_defexp` → no expression operator parsing happens
- At expression level, they go through shunting yard → operators work fine

## The Solution (From User Guidance)

> "ensure the shunting yard parser recognises the *first* value as a legal position for the control flow keywords, and 2) then remove the parse_if, parse_while etc. from parse_subexp so that they are handled entirely by the shunting yard parser."

### Steps Required

1. **Remove control flow from `parse_defexp`**
   - Remove `parse_if_unless`, `parse_while`, `parse_until`, `parse_for`, `parse_begin` from line 484
   - Force ALL control flow to go through `parse_subexp` → shunting yard

2. **Fix the keyword stopping logic in shunting yard**
   - Current logic (shunting.rb lines 162-171) stops at keywords unless they're the second operand of an infix operator
   - Need to ALSO allow control flow keywords when they're the first value in a fresh expression
   - Challenge: Distinguish "first value in fresh expression" from "statement in a block of statements"

3. **Method chaining and all operators work automatically**
   - Once control flow goes through shunting yard, all expression operators (`.`, `+`, etc.) work naturally
   - No special-case logic needed

## The Challenge: Nested Parsing Contexts

The hard part is step 2. Consider this code:

```ruby
def foo
  x = 1        # First statement in method body
  if true      # Second statement - should NOT be parsed by expression shunting yard
    y = 2
  end
end
```

vs.

```ruby
result = if true; 42; end.to_s  # SHOULD be parsed entirely by shunting yard
```

### How Nested Parsing Works

When parsing `if true; 42; end` inside a while body:

1. `parse_while` is called
2. `parse_while` → `parse_opt_defexp` (for body)
3. `parse_opt_defexp` → `kleene { parse_exp }`
4. Each `parse_exp` → `parse_defexp` → `parse_subexp`
5. Each `parse_subexp` creates a NEW shunting yard instance via `@shunting.parse()`
6. That new instance has `ostack.empty() == true`

So we can't just use `ostack.empty()` to detect "first value in fresh expression" because EVERY statement in a block creates a fresh shunting yard with empty stack.

### What We Need to Detect

**Allow control flow keywords when**:
- Parsing the RHS of an assignment: `x = if true; 42; end`
- After any infix operator: `result + if cond; val; end`
- Inside parentheses: `(if true; 1; end)`
- In array/hash literals: `[if true; 1; end]`
- As method arguments: `foo(if true; 1; end)`

**Stop at control flow keywords when**:
- Parsing statements in a block: `x = 1; if true; ... end; y = 2`
- Not in the context of an operator expecting a value

### Potential Approaches

#### Option 1: Check Operator Stack State
If there's an operator on the stack waiting for a right-hand value, allow control flow:
```ruby
allow_control_flow = !ostack.empty? && ostack.last.type == :infix
```

But this fails for the first statement case where `ostack.empty() == true` yet we're at statement level.

#### Option 2: Pass Context to `parse()`
Add a parameter to `@shunting.parse(mode)` where mode is:
- `:expression_value` - allow control flow keywords
- `:statement` - stop at control flow keywords

Then track the mode through the parse chain.

#### Option 3: Check Parse Call Stack
Examine what called `parse_subexp`:
- If called from shunting yard's operator parsing → expression context
- If called from `parse_exp` → statement context

But this is fragile and hard to implement.

#### Option 4: Let Statement Parser Handle It Differently
Instead of removing control flow from `parse_defexp`, change parse_defexp to:
1. Try `parse_subexp` first
2. If it returns a control flow structure, check if next token is an operator
3. If yes, re-parse through shunting yard to include operators
4. If no, return the structure as-is

But this is complicated and still doesn't properly solve the problem.

## Session 46 Investigation Results

### What We Tried

1. **Removed control flow from `parse_defexp`** → Parse error in `lib/core/object.rb:25`
   - The `else` keyword wasn't being recognized by nested parsing
   - Control flow inside method bodies broke

2. **Modified keyword stopping logic with `ostack.empty() && opstate == :prefix`** → Wrong
   - Every new shunting yard instance has `ostack.empty()` true
   - Caused nested control structures to incorrectly parse subsequent statements

3. **Implemented `parse_method_chain` hack** → REJECTED
   - Only handled method chaining, not general expression contexts
   - Violated architecture
   - See `docs/REJECTED_APPROACH_METHOD_CHAINING.md`

### Debug Findings

When we removed control flow from `parse_defexp`, the error was:

```
lib/core/object.rb:25: Parse error: Expected: expression or 'end' for open def 'raise'
```

This was at:
```ruby
def raise(msg_or_exc)
  if msg_or_exc.is_a?(StandardError)
    exc = msg_or_exc
  else      # ← Error here
    exc = RuntimeError.new(msg_or_exc)
  end
end
```

The `if` at line 23 was being parsed by the shunting yard, which then consumed the `end` at line 27, leaving no `end` for the method definition at line 21.

This suggests the nested shunting yard wasn't properly stopping at `else` or wasn't properly handling the if/else/end structure.

## What Needs to Be Done

1. **Understand the exact control flow** when `parse_if_unless` is called from the shunting yard
   - How does it call back into `parse_opt_defexp`?
   - How do those nested parser calls create new shunting yards?
   - Why doesn't the nested shunting yard stop at `else`?

2. **Design a proper context tracking mechanism**
   - Determine if we need to pass context to `parse()`
   - Or if we can infer context from the state
   - Or if we need a different architectural approach

3. **Implement and test carefully**
   - Start with simple cases
   - Build up to complex nested structures
   - Ensure all existing code still compiles

## Blocking Specs

These RubySpec files fail specifically because of this issue:

- `if_spec.rb` - Line 71: `end.should == 123`
- `while_spec.rb` - Line 65: `end.should == nil`
- `until_spec.rb` - Similar issues
- Likely others that test control flow as expressions

## Recommendation

This is **complex parser architecture work** that requires:
1. Deep understanding of the recursive parsing flow
2. Careful design of context tracking
3. Thorough testing to avoid breaking existing code
4. Time to investigate and get it right

**Do not attempt quick fixes or hacks.** This needs proper architectural design and implementation.

The payoff is significant: Once done, control flow structures will work as expressions in ALL contexts, not just method chaining. This unblocks multiple RubySpec files and makes the compiler more complete.
