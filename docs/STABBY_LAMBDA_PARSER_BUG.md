# Stabby Lambda Parser Bug After Newlines

## Summary

Commit a2c2301 "Fix parser bug: negative numbers after newlines now parse correctly" introduced a regression where expressions following stabby lambda method calls are incorrectly parsed as block arguments instead of separate statements.

## Minimal Reproducer

**File:** `test/test_stabby_block.rb`

```ruby
-> { x }.a
lambda { y }
```

## Symptoms

### Parse Tree at d2f8905 (CORRECT - Last Working Commit)
```
(callm (lambda () (x)) a)
(lambda () (y))
```
Two separate statements.

### Parse Tree at a2c2301 (BROKEN - First Failing Commit)
```
(callm (lambda () (x)) a lambda (proc () (y)))
```
The second `lambda { y }` is incorrectly parsed as a **block argument** to the method call `.a`.

### Runtime Behavior
- **At d2f8905:** Code runs successfully
- **At a2c2301+:** Segfault due to malformed AST

## Key Observations

1. **The first expression MUST be a stabby lambda** (`->`) for the bug to occur
2. **The second expression can be either** stabby lambda or keyword lambda - both are misparsed
3. **Keyword lambda first works correctly:**
   ```ruby
   lambda { x }.a
   lambda { y }
   ```
   This parses correctly even at a2c2301.

## Root Cause

The fix for negative numbers after newlines in commit a2c2301 modified `tokens.rb`:

```ruby
# If nolfws stopped at a newline, set @lastop = true so next token starts new expression
if @__at_newline
  @lastop = true
else
  @lastop = res && res[1] && (!res[1].is_a?(Oper) || res[1].type != :rp)
end
```

This change sets `@lastop = true` after newlines to ensure `-4` in:
```ruby
4.ceildiv(-3)
-4.ceildiv(3)
```
is parsed as unary minus instead of binary subtraction.

### Unintended Side Effect

After parsing:
```ruby
-> { x }.a
```

The tokenizer encounters a newline and sets `@lastop = true`. When the parser then sees `lambda` on the next line with `@lastop = true`, it interprets this as a valid block argument continuation to the method call `.a`.

### Why Keyword Lambda Works

When the first expression is a keyword lambda (`lambda { x }.a`), the tokenization state after the method call is different, and the `@lastop = true` mechanism doesn't trigger the same block-argument parsing path.

## Breaking Commit

**Commit:** a2c2301a501bf54a8b3b7db25fa2dd7079066689
**Author:** Vidar Hokstad
**Date:** Thu Oct 16 19:18:09 2025 +0100
**Message:** Fix parser bug: negative numbers after newlines now parse correctly

**Files Changed:**
- `tokens.rb` - Added `@__at_newline` tracking and `@lastop = true` after newlines
- `shunting.rb` - Whitespace change only
- `test/selftest.rb` - Added tests for negative number parsing

## Impact

This regression broke 25 RubySpec tests that transitioned from `[FAIL]` to `[SEGFAULT]`:
- Integer specs (right_shift_spec, ceildiv_spec, ceil_spec, etc.)
- Any code pattern with stabby lambda method calls followed by newlines

The specs that use mock objects with method chains like:
```ruby
obj = mock("test")
obj.should_receive(:method).and_return(value)
-> { code }.should.raise_error(Exception)
-> { code }.should.raise_error(Exception)  # This line misparsed as block to first lambda
```

## Testing the Bug

### View Parse Trees
```bash
# At d2f8905 (correct)
git checkout d2f8905
ruby -I. driver.rb test/test_stabby_block.rb --parsetree --norequire --notransform

# At a2c2301 (broken)
git checkout a2c2301
ruby -I. driver.rb test/test_stabby_block.rb --parsetree --norequire --notransform
```

### Compile and Run
```bash
# At d2f8905 (works)
git checkout d2f8905
./compile test/absolute_minimal.rb -I .
./out/absolute_minimal

# At a2c2301 (segfaults)
git checkout a2c2301
./compile test/absolute_minimal.rb -I .
./out/absolute_minimal  # Segmentation fault
```

## Test Files

1. **test/test_stabby_block.rb** (3 lines) - Minimal parser reproducer
2. **test/absolute_minimal.rb** (12 lines) - Minimal runtime reproducer with method call

## Fix Applied (2025-10-17)

### Status: ✅ FIXED

The fix required coordinated changes across multiple components:

### 1. **tokens.rb** (Tokenizer Layer)
- Added `:lambda` to Keywords set so it's recognized as a keyword
- Modified `@lastop` logic: only set `true` after newlines if **previous token was an operator**
- Added `@newline_before_current` tracking to detect when `ws()` skipped a newline
- Reset `@lastop = true` at start of `each()` to properly initialize for new parses

**Key insight**: Method names don't have operator tokens, so checking `old_last[1]` prevents triggering `@lastop = true` after method calls like `.a`

### 2. **parser.rb** (Parser Layer)
- Added `parse_lambda` to the parse chain in `parse_defexp` so lambda is properly handled as a keyword

### 3. **shunting.rb** (Expression Parser Layer)
- Modified block argument handling to check `!@tokenizer.newline_before_current` before calling `parse_block()`
- This prevents blocks after newlines from being treated as method arguments

### 4. **tokenizeradapter.rb** (Adapter Layer)
- Added `newline_before_current` forwarding method

### How It Works

The fix distinguishes between two scenarios:

1. **After operators** (like `)` from method calls with parens):
   ```ruby
   4.ceildiv(-3)  # Previous token: ), operator type :rp
   -4.ceildiv(3)  # @lastop not set, so ws() skips newline, allows negative number
   ```

2. **After method names** (like `a` from `.a`):
   ```ruby
   -> { x }.a     # Previous token: method name 'a', no operator
   lambda { y }   # @lastop false, newline NOT skipped, separate statement
   ```

### Verification

```bash
# Parse tree now correct
ruby -I. driver.rb test/test_stabby_block.rb --parsetree --norequire --notransform
# Output: Two separate statements

# Negative numbers still work
./compile test/test_negative3.rb -I .
./out/test_negative3  # Works correctly

# Minimal reproducer compiles
./compile test/absolute_minimal.rb -I .
./out/absolute_minimal  # No segfault
```

## Related Commits

- **d2f8905** - "Reduce SEGFAULT count from 32 to 25 by fixing Integer methods" (last working)
- **a2c2301** - "Fix parser bug: negative numbers after newlines now parse correctly" (introduced regression)
- **Current** - "Fix stabby lambda parser bug: prevent block argument misparsing after newlines" (fixed)

## References

- Original issue: Negative numbers after newlines parsed as binary subtraction
- Fixed: `4.ceildiv(-3)\n-4.ceildiv(3)` now parses correctly ✅
- Also fixed: Stabby lambda method calls followed by expressions on new line ✅
