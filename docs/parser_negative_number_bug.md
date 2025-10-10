# Parser Bug: Negative Number Parsing Context Sensitivity

## Summary

The parser incorrectly interprets `-4.method_call` as binary subtraction rather than unary negation when it appears after certain expressions, specifically after method calls with negative arguments.

## Discovered

2025-10-10, while investigating ceildiv_spec.rb segfault

## Minimal Test Case

**TRULY MINIMAL** (2 lines, no complexity):
```ruby
4.abs
-4.abs   # ✗ Parsed as: (4.abs) - (4.abs) = 0
```

**With method arguments**:
```ruby
4.ceildiv(-3)
-4.ceildiv(3)  # ✗ Parsed as: (4.ceildiv(-3)) - (4.ceildiv(3))
```

**Even fails with puts** (won't compile):
```ruby
puts -4.abs  # ✗ Compilation error: "Incomplete expression"
```

## Parse Tree Evidence

When both lines are present:
```
(callm (sexp 9) ceildiv ((sexp -5)))  # First line: 4.ceildiv(-3) - correct
(call (callm (sexp 1) - (...)))       # Second line: WRONG! Parsed as (1 - ...)
```

Expected for second line:
```
(callm (sexp -7) ceildiv ((sexp 7)))  # -4.ceildiv(3)
```

## Root Cause

The parser's lookahead after processing a method call with a negative number in parentheses causes it to treat the next `-` as a binary operator instead of a unary operator.

This is a **parser precedence/context bug** in how the tokenizer or parser handles `-` after completing an expression.

## Workaround

Always parenthesize negative numbers when they are receivers:
```ruby
# Bad (may parse incorrectly):
-4.ceildiv(3)

# Good (always works):
(-4).ceildiv(3)
```

## Impact

- Affects any code with consecutive expressions where:
  1. First expression contains a negative number
  2. Second expression starts with a negative number as a receiver

- This is particularly problematic in spec files with multiple assertions

## Files Affected

- Parser: `parser.rb`, `shunting.rb`, `tokens.rb`
- The issue is in expression parsing when determining if `-` is unary or binary

## Technical Analysis

The tokenizer uses `@lastop` flag to decide if `-` should be treated as unary (after operators) or binary (after values). The problem:

1. After `)`, `@lastop` is set to `false` (because `)` is not an operator)
2. The tokenizer calls `nolfws` which skips spaces but not newlines
3. The newline remains in the stream, but `prev_lastop` is still `false`
4. When `-` is encountered, it's treated as binary because `prev_lastop == false`

**Why tokenizer fix doesn't work**: The tokenizer cannot know if an expression is complete at a newline. For example:
- `x = 1\n+ 2` - newline doesn't end expression (should continue)
- `foo()\n-4` - newline ends expression (should start new)

This requires **expression-aware context** which only exists in the parser (`shunting.rb` or `parser.rb`), not the tokenizer.

**Proper fix location**: The Shunting Yard parser in `shunting.rb` should detect when an expression is complete and reset the state for the next line. Alternatively, `parser.rb` could handle statement boundaries more explicitly.

## Priority

**MEDIUM** - This causes silent misparsing that leads to runtime crashes, and affects multiple specs. However, workaround (use parentheses) is simple and the fix is complex.

## Related

- Similar to issues documented in DEBUGGING_GUIDE.md about expression combination bugs
- May be related to how the Shunting Yard algorithm handles operator precedence after certain token sequences
