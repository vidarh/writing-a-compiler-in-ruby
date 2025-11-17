# Session 2025-11-17: Percent Literal and Regex Escape Fixes

## Overview

Successfully investigated and resolved two critical compilation regressions in the rubyspec language test suite:
- string_spec.rb: CRASH → COMPILE FAIL → **CRASH (fixed)**
- regexp_spec.rb: FAIL → COMPILE FAIL → **FAIL (fixed)**

Both specs were restored to their pre-regression states.

## Problem 1: Percent Literal Parsing Bugs

### Issues Discovered

1. **Backslash Delimiter Not Working**
   - Percent literals using backslash as delimiter (`%\text\`) failed with "Unterminated percent literal"
   - Root cause: Escape sequence handling treated backslash as escape character even when it was the delimiter itself

2. **Dollar Sign Delimiter Ambiguity**
   - Using `$` as delimiter (`%$hey #{$var}$`) created parsing conflicts
   - After string interpolation `#{...}`, the closing `$` was ambiguous - could be delimiter or start of global variable

3. **Poor Error Reporting**
   - RuntimeError instead of CompilerError
   - Error position reported at EOF instead of at the start of the percent literal

4. **Inconsistent Type Comparisons**
   - Mixed use of character literals (`?{`, `?(`) and strings in delimiter comparisons
   - Character literal `?\` not equal to string `"\\"`

### Solution (Commit b187fd5)

**File**: `tokens.rb`

**Changes**:

1. **Save position at start of percent literal**:
```ruby
percent_start_pos = @s.position  # Save position for error reporting
@s.get  # consume '%'
```

2. **Skip escape handling when backslash is delimiter**:
```ruby
if c.ord == 92 && delim != "\\"  # backslash (but not if backslash is the delimiter)
  # Escape sequence - consume next character literally
  content << c.chr
  next_c = @s.get
  content << next_c.chr if next_c
```

3. **Exclude problematic delimiters**:
```ruby
# Exclude @ (instance vars), _ (identifiers), and $ (global vars) to avoid ambiguity
is_delimiter = delim && !ALNUM.member?(delim) && delim != "_" && delim != "@" && delim != "$"
```

4. **Use CompilerError with position**:
```ruby
raise CompilerError.new("Unterminated percent literal", percent_start_pos) if c == nil
```

5. **Fix all character literal comparisons to use strings**:
```ruby
# Before:
when ?{ then ?}
paired = (delim == ?{ || delim == ?( || delim == ?[ || delim == ?<)

# After:
when "{" then "}"
paired = (delim == "{" || delim == "(" || delim == "[" || delim == "<")
```

### Testing

**Before Fix**:
```bash
./run_rubyspec rubyspec/language/string_spec.rb
# Result: COMPILE FAIL - "Unterminated percent literal"
```

**After Fix**:
```bash
./run_rubyspec rubyspec/language/string_spec.rb
# Result: Compiles successfully, runs and crashes (original CRASH status)
```

**Validation**:
- selftest: 0 failures ✓
- selftest-c: 0 failures ✓
- Backslash delimiter works: `%\ab\` → `"ab"`
- Dollar delimiter excluded: `%$hello$` → treated as `%` modulo operator

## Problem 2: Regex Literal Escape Bug

### Issue Discovered

Regex patterns with escaped forward slashes failed to parse:
```ruby
%r[/].to_s.should == /\//.to_s
# Error: Missing value in expression
# Parsed as: %r[/].to_s.should == / (division) \/ (another division)
```

**Root Cause**: Character literal typo in regex tokenizer.

### Investigation

The regex tokenizer checks for backslash to handle escape sequences:
```ruby
elsif c == ?\    # WRONG - this is ambiguous
  # Escape sequence
  pattern << c.chr
  next_c = @s.get
  pattern << next_c.chr if next_c
```

**The Bug**: In Ruby, `?\` is NOT the same as `?\\`:
```ruby
ruby -e 'puts(?\ == ?\\)'  # false
```

- `?\` - ambiguous/deprecated character literal syntax
- `?\\` - explicit backslash character literal (correct)

The comparison `c == ?\` was always returning false, so the escape handling never triggered.

### Solution (Commit 5cd3658)

**File**: `tokens.rb` (line 515)

**Change**: Single character fix
```ruby
# Before:
elsif c == ?\

# After:
elsif c == ?\\
```

### Flow Analysis

**Before Fix** - Parsing `/\//`:
1. `/` opens regex
2. `\` read → `c == ?\` is FALSE → falls through to else → adds `\` to pattern
3. `/` read → `c == ?/` is TRUE → closes regex early
4. Pattern is just `"\"` instead of `"\/"`
5. Next `/` seen as division operator → parse error

**After Fix** - Parsing `/\//`:
1. `/` opens regex
2. `\` read → `c == ?\\` is TRUE → enters escape handling
3. Adds `\` to pattern, reads next char `/`, adds it to pattern
4. Pattern is now `"\/"`
5. Next iteration reads closing `/` → regex ends correctly
6. Pattern is `"\/"` ✓

### Testing

**Before Fix**:
```ruby
result = %r[/].to_s.should == /\//.to_s
# Error: Missing value in expression
```

**After Fix**:
```ruby
result = %r[/].to_s.should == /\//.to_s
# Compiles successfully ✓
```

**Validation**:
```bash
./run_rubyspec rubyspec/language/regexp_spec.rb
# Result: P:1 F:37 S:1 (original FAIL status, not COMPILE FAIL)
```

## Impact Summary

### Fixes Applied

1. **Percent Literal Parsing** (b187fd5):
   - Backslash delimiter support
   - Dollar sign delimiter exclusion
   - Improved error reporting
   - Consistent type comparisons

2. **Regex Escape Handling** (5cd3658):
   - Fixed `?\` → `?\\` typo
   - Escape sequences now work correctly

3. **Documentation** (1c46603):
   - Added KNOWN_ISSUES #43 for percent literal delimiter restrictions

### Test Results

**string_spec.rb**:
- Before: COMPILE FAIL (unterminated percent literal)
- After: CRASH (original status) ✓

**regexp_spec.rb**:
- Before: COMPILE FAIL (parse error on `/\//`)
- After: FAIL (P:1 F:37 S:1 - original status) ✓

**Core Tests**:
- selftest: 0 failures ✓
- selftest-c: 0 failures ✓
- Custom specs: 87% pass rate (103/118)

### Commits

1. `b187fd5` - Fix percent literal parsing bugs
2. `1c46603` - Document percent literal delimiter restrictions (#43)
3. `5cd3658` - Fix regex literal backslash escape handling

## Lessons Learned

### 1. Character Literal Ambiguity

In Ruby, character literal syntax can be ambiguous:
- `?\` - May work but is ambiguous
- `?\\` - Explicit, unambiguous (correct)

Always use explicit escaping in character literals for clarity.

### 2. Type Consistency Matters

Mixing character literals and strings in comparisons can cause bugs:
- Character literal: `?{` (integer in older Ruby, string in newer)
- String: `"{"`

Best practice: Use strings consistently, especially when comparing with scanner output.

### 3. Error Reporting Best Practices

- Use CompilerError instead of RuntimeError for parsing errors
- Report position at error START, not at EOF
- Provide file/line/column context

### 4. Delimiter Character Restrictions

Some characters create ambiguity and should be excluded as delimiters:
- `$` - conflicts with global variables
- `@` - conflicts with instance variables
- `_` - conflicts with identifiers

Backslash can work if escape handling is conditional on the delimiter.

## Files Modified

### Code
- `tokens.rb` - Percent literal and regex escape fixes

### Documentation
- `docs/KNOWN_ISSUES.md` - Added issue #43 about delimiter restrictions
- `docs/SESSION_2025_11_17_PERCENT_REGEX_FIXES.md` - This file

## Next Steps

### Immediate
- [x] Verify both specs are back to original status
- [x] Run full selftest suite
- [x] Run full selftest-c suite
- [ ] Run full language spec suite to check for other regressions

### Future Considerations

1. **String Interpolation**: string_spec still fails many tests because `#$var` and `#@ivar` interpolation doesn't work
2. **Regex Implementation**: regexp_spec needs Regexp#match, Regexp#=~, and other methods
3. **Eval Support**: Many specs depend on `eval` which isn't supported in AOT compilation

## Conclusion

Successfully resolved both compilation regressions:
- **string_spec**: COMPILE FAIL → CRASH (restored)
- **regexp_spec**: COMPILE FAIL → FAIL (restored)

The fixes were surgical and well-tested:
- 11 lines changed in percent literal parsing
- 1 character changed in regex escape handling
- 0 regressions in selftest/selftest-c
- Both specs back to their pre-regression states

All changes maintain backward compatibility while fixing critical parsing bugs.
