# Control Flow as Expressions - Architectural Blocker

## Status

**BLOCKED** - Requires architectural parser redesign. Blocks 5+ language specs.

**Referenced in**: TODO.md:80-82

## Problem Statement

In Ruby, **all control structures are expressions** that return values and can be used in any expression context. The compiler currently only supports control structures as expressions in assignment contexts (`x = if...`), but not in other expression contexts (method chaining, arithmetic, array literals, etc.).

### What Works ✅

```ruby
# Assignment context
result = if true; 42; end                    # ✓ Works
x = while i < 10; i += 1; break i; end      # ✓ Works

# case expressions (fully functional)
result = case x
when 1 then "one"
when 2 then "two"
end.upcase                                   # ✓ Works
```

### What Doesn't Work ❌

```ruby
# Method chaining at statement level
if true; 42; end.to_s                        # ✗ Parse error

# All other expression contexts
(if true; 5; end) + 10                       # ✗ Parse error
[if true; 1; end, 2]                         # ✗ Parse error
puts(if true; "yes"; end)                    # ✗ Parse error
{ key: if true; "val"; end }                 # ✗ Parse error
```

**Error**: "Method call requires two values, but only one was found"

**Root cause**: Control structures parsed at statement level don't go through the shunting yard, so operators after them have no left-hand value.

## Affected Specs

From language specs (TODO.md:80):
- `case_spec` (different error - splat in when)
- `metaclass_spec`
- `symbol_spec`
- `unless_spec`
- `while_spec`

All fail with pattern: trying to call methods on control structure return values.

## Architectural Issue

Control flow keywords are parsed in **TWO places**:

1. **`parse_defexp`** (parser.rb:484) - Statement-level parsing
   - When parser sees `if`/`while`/etc at statement level
   - Calls specific parser methods (`parse_if_unless`, `parse_while`, etc.)
   - Result is NOT passed through shunting yard
   - No operator parsing happens after the control structure

2. **Shunting yard** (shunting.rb:191-202) - Expression-level parsing
   - When `if`/`while`/etc appears after an assignment operator
   - Shunting yard calls parser method, gets result as expression value
   - Can have operators (including `.` method calls) applied to it

### Why `case` Works But Others Don't

`case` is in `@escape_tokens` (tokenizeradapter.rb:19), which forces the entire `case..end` structure to be yielded as a value to the shunting yard. Other control structures are not in `@escape_tokens`, so they're parsed statement-by-statement.

## Solution Approach (From User Guidance)

> "ensure the shunting yard parser recognises the *first* value as a legal position for the control flow keywords, and 2) then remove the parse_if, parse_while etc. from parse_subexp so that they are handled entirely by the shunting yard parser."

### Required Steps

1. **Remove control flow from `parse_defexp`**
   - Remove `parse_if_unless`, `parse_while`, `parse_until`, `parse_for`, `parse_begin` calls
   - Force ALL control flow through `parse_subexp` → shunting yard

2. **Fix shunting yard keyword stopping logic**
   - Current logic (shunting.rb:162-171): Allow keywords as second operand of infix operators
   - Needed: ALSO allow control flow keywords as first value in fresh expression
   - **Challenge**: Distinguish "first value in expression" from "statement in sequence"

3. **All operators work automatically**
   - Once control flow goes through shunting yard, method chaining/arithmetic/etc. work naturally

## The Challenge: Context Detection

**The hard problem is nested parsing contexts:**

```ruby
def foo
  x = 1        # Statement
  if true      # Statement - should NOT parse as expression value
    y = 2
  end
end
```

vs.

```ruby
result = if true; 42; end.to_s  # SHOULD parse as full expression
```

When `parse_while` calls `parse_opt_defexp` for its body, which calls `parse_exp`, which calls `parse_defexp`, which calls `parse_subexp`, which creates a NEW shunting yard instance... that instance has `ostack.empty() == true` even though it's NOT parsing a fresh expression value - it's parsing statements in the while body.

**Problem**: Each shunting yard instance doesn't know "am I parsing an expression value or a statement sequence?"

## Previous Attempts and Failures

### Attempt 1: Add All Keywords to @escape_tokens (Session 45)

Added `:while`, `:if`, `:unless`, `:begin` to `@escape_tokens`.

**Result**: FAILED - broke selftest in lib/core/object.rb

**Why**: Caused parser to consume too much at statement level.

### Attempt 2: Modify Keyword Stopping Logic (Session 46)

Tried allowing control flow keywords when `ostack.empty() && opstate == :prefix`.

**Result**: FAILED - nested control structures parsed wrong `end` tokens

**Example of failure**:
```ruby
while i < len
  # ... statements ...
end
if neg          # This 'if' was consumed by while's shunting yard
  # ...
end
```

The `while` loop's shunting yard instance incorrectly tried to parse the `if` at line 330 as part of the while body, consuming the wrong `end` token.

### Attempt 3: parse_method_chain Hack (Session 46) - REJECTED

Implemented manual checking for `.` tokens after control structures.

**Why rejected**: Only handles one specific case (method chaining), leaving all other expression contexts broken. The proper fix (shunting yard) would handle ALL contexts automatically. (Full analysis was in REJECTED_APPROACH_METHOD_CHAINING.md, removed — retained in git history; lessons captured in Attempt 3 section above.)

## Lessons from Session 46

1. **Don't hack around architectural issues** - fix them properly
2. **The hack only solves 1 of N problems** - Method chaining is just one expression context
3. **Follow user guidance** on architectural solutions
4. **Context information** must be passed to shunting yard instances somehow

## Potential Solutions (Not Implemented)

1. **Pass context flag to shunting yard**: Add parameter indicating "expression value context" vs "statement sequence context"

2. **Check operator stack state**: If there's an assignment or infix operator, we're parsing a value

3. **Track parser state**: Parser tracks whether it's in "expression value context" or "statement sequence context"

None attempted because they require careful architectural design.

## Next Steps (When Resumed)

This is **complex parser architecture work** that requires:

1. Deep analysis of how nested shunting yard instances are created
2. Design decision on how to communicate context to shunting yard instances
3. Careful implementation of keyword stopping logic
4. Thorough testing of nested control structures
5. Remove control flow keywords from `parse_defexp` once shunting yard handles them

**Cannot be rushed** - architectural correctness is critical.

## References

- TODO.md:80-82 - Task tracking
- REJECTED_APPROACH_METHOD_CHAINING.md (removed — retained in git history)
- Session 45 commit e64156e - Partial solution (expression context only)
- Session 46 - Failed architectural attempt
