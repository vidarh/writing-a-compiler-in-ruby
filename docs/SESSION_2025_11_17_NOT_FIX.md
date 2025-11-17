# Session 2025-11-17: Fix `not not` Operator Bug

## Summary

Fixed a critical bug in the shunting yard parser that prevented consecutive prefix operators from being parsed correctly. The expression `not not false` was being misparsed as a destructuring assignment instead of a double negation.

## Problem

When parsing `not not false`, the parser was creating an incorrect parse tree:
```ruby
# Wrong (before fix):
(assign (destruct ! x) (! false))

# Correct (after fix):
(assign x (callm (callm false !) !))
```

The first `not` operator was being reduced too early, causing the second `not` to be treated as a variable name in a destructuring assignment.

## Root Cause

In `shunting.rb` line 68, the reduce() method had a condition to prevent reducing prefix operators when a higher-precedence prefix operator follows:

```ruby
# Before:
!(ostack.last.type == :prefix && op && op.type == :prefix && pri < ostack.last.pri)
```

This only prevented reduction when the incoming operator had HIGHER precedence (`pri < ostack.last.pri`). When two prefix operators had EQUAL precedence (like `not not`, both with pri=7), the first would be reduced prematurely.

## Solution

Changed the condition to also prevent reduction when precedences are equal:

```ruby
# After:
!(ostack.last.type == :prefix && op && op.type == :prefix && pri <= ostack.last.pri)
```

This ensures that `not not false` parses correctly as `not (not false)` instead of the malformed `(not) not false`.

## Investigation Process

1. Found that `precedence_spec.rb` was failing on `not not false` expression
2. Tested with `--notransform --parsetree` to see raw parse tree
3. Discovered the parser was creating a destructuring assignment
4. Added debug output to scanner (tokens.rb) to verify both `not` tokens were being recognized as operators
5. Added debug to shunting yard to trace operator processing
6. Found that both `not` operators were correctly tokenized with operator objects
7. Discovered the bug was in the `reduce()` method's precedence check
8. Made the one-character fix: `<` to `<=`

## Testing

- Created `spec/not_not_spec.rb` with 2 tests - both passing
- Selftest: 0 failures
- Verified `not not false` produces correct parse tree
- Verified `not not 10` produces correct result

## Files Modified

- `shunting.rb`: Fixed prefix operator precedence handling in reduce() method
- `spec/not_not_spec.rb`: Added test coverage for double `not` operator

## Commit

```
bb186a0 Fix shunting yard to handle consecutive prefix operators
```

## Impact

This fix enables any consecutive prefix operators with equal precedence to work correctly, not just `not not`. Examples that now work:
- `not not false` → `false`
- `not not 10` → `true`
- `!!false` → `false` (already worked, since `!` is a symbol operator)

## Notes

- The `!` operator already worked because it's tokenized as a symbol character, not a keyword
- MRI Ruby requires parentheses for `not not` on a single line: `x = (not (not false))`
- Our compiler is more permissive and allows `x = not not false` without parentheses
- This is acceptable as it matches the intended semantics

## Session Continuation: Percent Literal Delimiter Fix

After completing the `not not` fix, I continued investigating COMPILE FAIL specs and found that `string_spec.rb` was failing due to a tokenizer bug with percent literals.

### Problem

Percent literals like `%=hey...=`, `%*hey...*`, `%-hey...-` were being misinterpreted as operators because the tokenizer only recognized a hardcoded list of delimiter characters.

### Root Cause

In `tokens.rb` line 401, the delimiter check was:
```ruby
if delim && (delim == ?{ || delim == ?( || delim == ?[ || delim == ?< || delim == ?| || delim == ?! || delim == ?/)
```

This only recognized 7 specific delimiters. When the tokenizer saw `%=hey...=`, it interpreted the `%=` as the modulo assignment operator instead of a percent literal with `=` as the delimiter.

### Solution

Changed to a general pattern that recognizes any non-alphanumeric character (except special characters @, $, _) as a valid delimiter:

```ruby
is_delimiter = delim && !ALNUM.member?(delim) && delim != ?_ && delim != ?@ && delim != ?$
if is_delimiter
```

This correctly handles percent literals with any punctuation character as the delimiter.

### Testing

- `string_spec.rb` now compiles successfully (changed from COMPILE FAIL to CRASH)
- Verified `%=` operator still works for modulo assignment: `a %= 3`
- Verified percent literals work with various delimiters: `%=hey...=`, `%*hey...*`
- Selftest: 0 failures

### Final Results

**COMPILE FAIL count reduced from 33 to 32** ✅

Summary statistics:
- Total spec files: 79
- Passed: 3
- Failed: 19
- Crashed: 25 (up from 24 - string_spec now compiles but crashes)
- **Failed to compile: 32** (down from 33)

## Commits

1. `bb186a0` - Fix shunting yard to handle consecutive prefix operators
2. `9118e46` - Fix percent literal delimiter detection

## Impact Summary

This session achieved:
- Fixed 2 bugs (parser and tokenizer)
- Reduced COMPILE FAIL count by 1 (3% reduction)
- Created test coverage for `not not` operator
- Improved percent literal handling to support all valid delimiters per Ruby spec
- All changes validated with selftest (0 failures)
