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

### 1. Proper Context Tracking

Track tokenizer state more accurately:
```ruby
@in_value_position = false  # true after values, false after operators

when ?%
  if @in_value_position
    return ["%", Operators["%"]]  # Modulo
  else
    # Parse percent literal
  end
```

Update `@in_value_position` after every token based on what it represents.

### 2. Reserved Handling for %s

Never treat `%s` as a percent literal:
```ruby
when ?%
  type_char = @s.peek
  if type_char == ?s
    # Let SEXParser handle it - just return % as operator
    return ["%", Operators["%"]]
  end
  # ... rest of percent literal logic
```

### 3. Statement Boundary Tracking

Track when we're at a statement boundary (where values are expected):
```ruby
@statement_boundary = true  # Set after newlines, semicolons, keywords

when ?%
  if @statement_boundary || @first || prev_lastop
    # Percent literal is valid here
  end
```

### 4. Alternative: Dedicated Percent Literal Token

Change the scanner to recognize percent literals before tokenization:
```ruby
# In scanner.rb, add dedicated method
def try_percent_literal
  return nil if @in_value_position
  # ... parse percent literal at scanner level
end
```

This keeps tokenizer simpler and prevents interaction with s-expressions.

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
