# Control Structures as Expressions - Architectural Issue

## Status: BLOCKED - Requires architectural changes

## Overview

In Ruby, **all control structures are expressions** that return values and can have methods called on them. The compiler currently treats most control structures as statements only, causing compilation failures in 5+ language specs.

## The Problem

### Failing Pattern

```ruby
while i < 3
  i += 1
end.should == nil  # Error: Missing value in expression
```

The error occurs because:
1. `while..end` is parsed as a statement, not an expression
2. When the shunting yard encounters `.should`, there's no value on the stack
3. Error: "Method call requires two values, but only one was found (:should)"

### Affected Specs (5 total)

From `docs/language_error_frequency_analysis.txt`:
- `case_spec` (different error - splat in when)
- `metaclass_spec`
- `symbol_spec`
- `unless_spec`
- `while_spec`

All fail with the same error pattern: trying to call methods on control structure return values.

## Current State: What Works

### ✅ `case` Expressions Work

```ruby
result = case x
when 1 then "one"
when 2 then "two"
end.upcase  # This WORKS
```

**Why it works:**
- `case` is in `@escape_tokens` (tokenizeradapter.rb:19)
- TokenizerAdapter yields the entire `case..end` AST to the shunting yard
- Shunting yard treats it as a value on the expression stack
- Methods can be called on it

### ❌ Other Control Structures Don't Work

```ruby
# ALL OF THESE FAIL:
x = if condition then 1 else 2 end     # Expected EOF
x = while cond; break 1; end           # Expected EOF
x = unless cond then 1 end.to_s        # Method call requires two values
x = begin; compute(); end.round        # Method call requires two values
```

## Investigation Results

### Attempted Fix #1: Add All Keywords to @escape_tokens

```ruby
@escape_tokens = {
  :lambda => :parse_defexp,
  :class => :parse_class,
  :module => :parse_module,
  :case => :parse_case,
  :while => :parse_while,        # Added
  :if => :parse_if_unless,       # Added
  :unless => :parse_if_unless,   # Added
  :begin => :parse_begin         # Added
}
```

**Result: FAILED** - Broke selftest with error in lib/core/object.rb:
```
Parse error: /app/lib/core/object.rb(235:1): Expected: expression or 'end'
```

**Why it failed:**
- The `@escape_tokens` mechanism works at the tokenizer level
- It applies **globally** to ALL occurrences of the keyword
- Can't distinguish between different contexts:
  - Expression context: `x = if cond then 1 end` ✓ should work
  - Statement modifier: `return if cond` ✗ broke this
  - Standalone statement: `if cond; do_thing; end` ✗ broke this

### Attempted Fix #2: Add Only :while

**Result: FAILED** - Same "Expected EOF" error at `end` keyword

The parser doesn't properly handle `while` as an expression even when it's in `@escape_tokens`. The tokenizer yields the keyword, but something in the parsing flow breaks.

## Root Cause: Architecture Limitations

### The Fundamental Issue

The parser has a **statement/expression dichotomy** that doesn't match Ruby's semantics:

1. **Expression parsing**: Handled by shunting yard (`parse_subexp`)
   - Sees: literals, variables, operators, method calls
   - Uses TokenizerAdapter with `@escape_tokens`

2. **Statement parsing**: Handled by `parse_defexp`
   - Sees: control structures, class/module defs, method defs
   - Returns AST nodes but doesn't integrate with shunting yard

3. **The mismatch**: In Ruby, control structures ARE expressions
   - They return values
   - They can be operands in larger expressions
   - Methods can be called on them

### Why @escape_tokens Worked for `case`

`case` has a **single grammatical role**: it's always a complete expression. It's never:
- A statement modifier (no `return case x`)
- A standalone statement without value usage

So adding it to `@escape_tokens` is safe.

### Why It Fails for if/while/unless/begin

These keywords have **dual roles**:

1. **As expressions** (should use `@escape_tokens`):
   ```ruby
   x = if cond then 1 else 2 end
   while cond; break val; end.to_s
   ```

2. **As statement modifiers** (can't use `@escape_tokens`):
   ```ruby
   return if condition
   next unless valid
   redo while retrying
   ```

3. **As standalone statements** (current implementation):
   ```ruby
   if condition
     do_something
   end
   # (next statement continues)
   ```

The `@escape_tokens` mechanism can't distinguish between these contexts because it operates at the **tokenizer level**, before the parser has context about how the keyword is being used.

## What Needs to Change

### Option 1: Context-Sensitive Escape Tokens (Complex)

Modify TokenizerAdapter to check **parsing context** before deciding whether to escape:
- In assignment context (`x = ...`): escape if/while/unless/begin
- After operators: escape them
- At statement position: don't escape
- After other tokens: escape

**Challenges:**
- Requires lookahead/lookbehind logic
- Parser state awareness in tokenizer (breaks separation of concerns)
- Fragile, hard to maintain

### Option 2: Unified Expression Parser (Major Refactoring)

Treat ALL constructs as expressions in the shunting yard:
- Remove the statement/expression split
- Parse control structures directly in shunting yard
- Handle statement modifiers as low-precedence postfix operators

**Challenges:**
- Major architectural change
- Risk of breaking existing functionality
- Significant testing required

### Option 3: Post-Parsing Expression Wrapper (Surgical)

When parsing statements at top level, check if they're followed by `.method`:
- Parse the control structure normally
- If next token is `.`, treat the structure as a value
- Continue parsing as method chain

**Challenges:**
- Requires modifying every control structure parser
- Doesn't solve assignment context (`x = while..end`)
- Inconsistent with Ruby's semantics

### Option 4: Parser Lookahead for Context Detection

Before parsing a keyword, check the **preceding context**:
```ruby
def parse_defexp
  # Check if we're in expression context
  in_expr_context = @in_assignment || @in_operator_rhs || @ostack.any?

  if keyword?(:while) && in_expr_context
    # Parse as expression via @escape_tokens
  else
    # Parse as statement
  end
end
```

**Challenges:**
- Requires tracking parser state
- Complex interaction with shunting yard
- May still not handle all cases

## Recommended Approach

**Phase 1: Add statement-position keywords incrementally**
- Keywords that are rarely/never used as modifiers
- Priority: `while` (no modifier usage in codebase), `begin`
- Test thoroughly with selftest and specs

**Phase 2: Implement context detection for if/unless**
- Add parser state tracking for expression vs statement context
- Use heuristics (after `=`, after operators, etc.)
- Extensive testing

**Phase 3: Long-term architectural fix**
- Move toward unified expression parsing
- Treat modifiers as postfix operators with low precedence
- Gradually refactor control structure parsing

## Testing Strategy

For any changes to this system:

1. **Selftest must pass** - This is the gate for all changes
2. **Manual test cases** - Create minimal reproductions:
   ```ruby
   # Expression context
   x = while false; end
   x = if true then 1 end

   # Method calls
   while false; end.to_s
   if true then 1 end.class

   # Statement modifiers (must not break)
   return if condition
   next unless valid
   ```
3. **Language specs** - Run affected specs to verify fixes
4. **No regressions** - Ensure case/lambda/class still work

## Related Files

- `tokenizeradapter.rb:15-21` - `@escape_tokens` definition
- `parser.rb:174` - `parse_while`
- `parser.rb:206` - `parse_begin`
- `parser.rb:268` - `parse_if_unless`
- `parser.rb:351` - `parse_defexp`
- `shunting.rb` - Expression parser (shunting yard)

## Impact

**Specs blocked:** 5+ language specs fail to compile
**Workaround:** None - fundamental limitation
**Priority:** Medium - blocks language spec progress but doesn't affect self-hosting

## Notes

- This issue reveals a broader architectural tension between statement-oriented and expression-oriented parsing
- Ruby's "everything is an expression" philosophy conflicts with the compiler's current design
- Any fix requires careful consideration of backward compatibility
- The `@escape_tokens` mechanism is elegant but limited to unambiguous keywords
