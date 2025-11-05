# Percent Literal Support Issue (bc8e8f2)

## Problem

Commit bc8e8f2 "Add heredoc and percent literal support to parser" added percent literal support that broke s-expression parsing. The implementation was reverted in 599483e.

## What Percent Literals Are

Percent literals are Ruby's alternative string/array literal syntax:
- `%Q{text}` or `%{text}` - Double-quoted string (interpolation)
- `%q{text}` - Single-quoted string (no interpolation)
- `%w{a b c}` - Array of strings (whitespace-separated)
- `%i{a b c}` - Array of symbols
- `%r{regex}` - Regular expression
- `%s{symbol}` - Symbol literal (deprecated in Ruby, but used for s-expressions in this compiler)

## Why They're Needed

RubySpec tests use percent literals extensively:
```ruby
str = %Q{This is a "quoted" string}
words = %w{one two three}
```

Current workaround in rubyspec_helper.rb:
```ruby
# Q constant as workaround for parser limitation with %Q{}
Q = lambda { |s| s }
# Usage: Q["text"] instead of %Q{text}
```

This workaround doesn't handle all cases and makes specs harder to read.

## Original Implementation

The implementation in tokens.rb (bc8e8f2) attempted to parse percent literals:

```ruby
when ?%
  @s.get  # consume %

  # Check if next char is a letter (type indicator)
  type_char = @s.peek
  type = nil
  if type_char && ALPHA.member?(type_char)
    type = type_char.chr
    @s.get
  end

  delimiter_char = @s.peek
  delimiter = delimiter_char ? delimiter_char.chr : nil

  # Heuristic: treat as percent literal if followed by delimiter
  is_common_delimiter = delimiter && "{[(<>|!/".include?(delimiter)
  if type || is_common_delimiter
    # Parse percent literal content
    # ...
  else
    # Treat as modulo operator
    @s.unget(type) if type
    return ["%", Operators["%"]]
  end
```

## Why It Broke

The implementation broke s-expression parsing because:

1. **S-expressions use `%s(...)` syntax** which should be handled by SEXParser
2. **SEXParser reads directly from Scanner**, not through Tokenizer
3. **Tokenizer was consuming `%s(` before SEXParser could see it**

This caused errors like:
```
Unhandled exception: undefined method 'each' for String
```

The s-expression parser expected to read `%s(...)` but got a String instead.

**Simple Fix for S-expressions**: The tokenizer should check if it sees `%s` and immediately unget it, letting the current handling fall through. The existing code already handles this correctly when `%` is treated as an operator.

## Context-Sensitivity Problem

The fundamental issue is that `%` is context-sensitive:
- After a value: `5 % 3` → modulo operator
- After an operator or at statement start: `x = %Q{text}` → percent literal

The implementation tried to use heuristics (checking what follows `%`) but this doesn't work:

### Insufficient Context Check
```ruby
# This check is too simplistic:
if @first || prev_lastop
  # Treat as percent literal
```

Fails in cases like:
- `str << 'e'` - Inside statement bodies where `@first=false, prev_lastop=false`
- After method names: `eval %Q{...}` - `@first=false, prev_lastop=false`
- Inside while/if bodies: `while true; puts %s(...); end`

### The Core Problem
Tokenization in Ruby requires knowing:
1. **What came before** (was previous token a value or operator?)
2. **Current context** (inside expression, statement, etc.)

Checking only `@first || prev_lastop` captures "start of file or after operator" but misses many valid contexts.

## Why S-expressions Were Affected

S-expressions in this compiler use `%s()` syntax:
```ruby
%s(if a b c)  # Creates [:if, :a, :b, :c]
```

This is NOT standard Ruby syntax but an internal compiler feature. SEXParser handles this specially by:
1. Reading `%s` directly from Scanner
2. Parsing the parenthesized content as symbolic expressions
3. Never going through normal tokenization

When the tokenizer tried to handle `%s(...)`, it:
1. Consumed the `%s`
2. Parsed the content as a string
3. Returned it as a string token
4. SEXParser never saw the `%s` prefix

## Current Workaround

Commit 599483e removed the entire percent literal implementation:
```ruby
# Reverted to:
when ?%
  # Fall through to operator handling
  # Now % is always treated as modulo
```

This means:
- `%s()` s-expressions work correctly again
- No percent literal support for strings/arrays
- Specs must use alternative syntax or workarounds

## Next Steps to Fix

### 1. Handle %s Special Case (REQUIRED)

Never treat `%s` as a percent literal - let it fall through to existing handling:
```ruby
when ?%
  # Check for %s - reserved for s-expressions
  @s.get  # consume %
  type_char = @s.peek
  if type_char == ?s
    # Unget the % and let existing code handle it
    @s.unget(?%)
    # Fall through to return % as operator
  else
    @s.unget(type_char) if type_char
    @s.unget(?%)
    # ... rest of percent literal logic using existing @first||prev_lastop
  end
```

### 2. Use Existing Context Mechanism

The tokenizer already has `@first` and `prev_lastop` (from @lastop tracking).
DO NOT add new state variables. Use what exists:
```ruby
when ?%
  # Check for %s first (see above)

  # Use existing context check
  if @first || prev_lastop
    # After operator or at start - try percent literal
    # Parse %Q{}, %w{}, %i{}, etc.
  else
    # After value - modulo operator
    return ["%", Operators["%"]]
  end
```

This is minimal and leverages existing infrastructure.

### 3. Fix Remaining Context Gaps

The `@first || prev_lastop` check doesn't catch all cases. Known gaps:
- Inside statement bodies (after `do`, after `;`)
- After method names like `eval %Q{...}`

**Fix**: Enhance existing @lastop mechanism to track these cases, don't add new variables.
Possible additions to what sets lastop=true:
- After `do` keyword
- After `;` semicolon
- After method names (already tracked via Keywords vs non-Keywords)

### 4. Incremental Implementation Strategy

Implement one percent literal type at a time, testing selftest after each:

1. **Start with %Q{}** (double-quoted string with interpolation)
   - Check which specs use it
   - Implement just %Q with `{}`delimiters
   - Test: `make selftest && make selftest-c`
   - Debug any failures before moving on

2. **Add %q{}** (single-quoted string, no interpolation)
   - Simpler than %Q (no escape processing)
   - Test after implementation

3. **Add %w{}** (array of words)
   - Split on whitespace
   - Test after implementation

4. **Add %i{}** (array of symbols)
   - Like %w but convert to symbols
   - Test after implementation

5. **Add other delimiters** if specs need them
   - `()`, `[]`, `<>`, `||`, etc.
   - Each delimiter pair separately tested

**Priority**: Only implement what specs actually test. Check spec files first.

### 5. Testing Strategy

Create test cases for all contexts:
```ruby
# After operators - should be percent literal
x = %Q{test}
y = 5 + %Q{test}

# After values - should be modulo
5 % 3
x % y

# After method names - should be percent literal
eval %Q{test}
puts %w{a b c}

# In statement bodies - should work for both
while true
  x = %Q{test}    # percent literal
  y = 5 % 3       # modulo
end

# S-expressions must still work
%s(if a b c)
```

## Files Affected

- `tokens.rb` - Tokenizer implementation
- `sexp.rb` - S-expression parser (must not be broken)
- `scanner.rb` - May need modification for proper solution

## Related Specs

Specs that need percent literals:
- All specs using `%w{}` for arrays
- Specs using `%Q{}` for strings with special characters
- Specs using `%i{}` for symbol arrays
- Specs using `%r{}` for regexes

Current workaround specs:
- Using `Q` constant for `%Q{}` in rubyspec_helper.rb
- Using `RUBY` constant for heredocs
