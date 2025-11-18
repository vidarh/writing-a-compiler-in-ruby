# Percent Literal Refactoring Plan

## Problem Statement

Percent literals (e.g., `%Q{...}`, `%$...$`, `%@...@`) are currently handled in two places:
1. **quoted.rb** - Handles proper interpolation and escape sequences
2. **tokens.rb** - Contains duplicate manual parsing that bypasses quoted.rb

The manual handling in tokens.rb:
- Incorrectly excludes `$` and `@` as delimiters (they are valid in Ruby)
- Does NOT handle string interpolation `#{...}` correctly
- Does NOT handle all escape sequences that quoted.rb supports
- Creates maintenance burden through code duplication

## Completed Work

### Step 0: Extract interpolation handling into reusable helper ✓
- Created `Quoted.handle_interpolation(s, ret, buf, &block)` helper in quoted.rb
- Refactored `expect_dquoted` to use this helper
- Verified no regressions with selftest

## Remaining Work

### Phase 1: Update escape handling in quoted.rb

**Goal**: Ensure quoted.rb has complete, correct escape handling for all percent literal types

**Relevant Spec**: `rubyspec/language/string_spec.rb` - Contains comprehensive escape sequence tests

**Tasks**:
1. Review `Quoted.escaped()` method for completeness
2. Compare against string_spec.rb escape tests:
   - `\n`, `\t`, `\r`, `\e` (basic escapes)
   - `\xHH` (hex escapes)
   - `\000` (octal escapes)
   - `\uHHHH` and `\u{HHHH}` (unicode escapes)
   - `\M-x` (meta escapes)
   - `\C-x` or `\c-x` (control escapes)
   - Delimiter escaping (e.g., `\$` when `$` is delimiter)
3. Add any missing escape handling
4. Test against string_spec.rb escape tests
5. Document which escapes work vs. don't work

**Acceptance Criteria**:
- All escape sequences in string_spec.rb either work correctly or are documented as unsupported
- No regressions in selftest or selftest-c

### Phase 2: Make tokens.rb use Quoted for percent literals

**Goal**: Remove duplicate percent literal parsing from tokens.rb

**Current State** (tokens.rb lines 399-556):
- Separate manual handling for `%Q` (lines 402-457)
- General percent literal handling (lines 458-552)
- Both bypass quoted.rb and lack interpolation support

**Approach**:
1. **Incremental replacement** - Replace one percent type at a time:
   - Start with `%Q{}` (most common, has interpolation)
   - Then `%q{}` (single-quoted, no interpolation)
   - Then `%w{}` and `%W{}` (word arrays)
   - Then `%i{}` and `%I{}` (symbol arrays)
   - Then `%x{}` (command execution)
   - Then `%r{}` (regexps)
   - Finally `%{}` (bare percent)

2. **Strategy for each type**:
   ```ruby
   # Instead of manual parsing, do:
   @s.unget("%")
   return [get_quoted_exp, nil]
   ```

3. **Handle delimiter validation in quoted.rb**:
   - Currently tokens.rb rejects `$`, `@`, `_` as delimiters
   - quoted.rb already correctly rejects only letters and digits
   - Remove these restrictions from tokens.rb

4. **Test after each change**:
   - Run selftest
   - Run selftest-c
   - Run string_spec.rb
   - Check for regressions

**Acceptance Criteria**:
- All percent literal types delegate to quoted.rb
- `$` and `@` work as delimiters
- Interpolation works in `%Q`, `%W`, `%I`, `%x`, `%r`
- No interpolation in `%q`, `%w`, `%i` (as expected)
- selftest and selftest-c pass
- string_spec.rb compiles (may still crash at runtime)

### Phase 3: Review remaining tokens.rb code

**Goal**: Identify further cleanup opportunities

**Questions to answer**:
1. Is there other duplicated string handling that should move to quoted.rb?
2. Are there other cases where tokens.rb manually parses when it should delegate?
3. Can we create additional helpers in quoted.rb to simplify tokens.rb?

**Process**:
1. Review all quote/string handling in tokens.rb
2. Identify duplication with quoted.rb
3. Create helpers in quoted.rb for common patterns
4. Incrementally replace duplicate code with helper calls
5. Test after each change

**Acceptance Criteria**:
- Documented list of potential cleanups
- No string/quote logic duplication between files
- Clear separation: quoted.rb handles parsing, tokens.rb handles tokenization

## Testing Strategy

After each phase:
1. `make selftest` - Must pass with expected 2 failures
2. `make selftest-c` - Must pass (self-compilation)
3. `make spec` - Custom specs must pass
4. `./run_rubyspec rubyspec/language/string_spec.rb` - Should improve or stay same
5. `./run_rubyspec rubyspec/language/` - Overall language specs shouldn't regress

## Success Criteria

- Percent literals with `$` and `@` delimiters work correctly
- String interpolation works in all percent literal types that support it
- All escape sequences work correctly
- No code duplication between tokens.rb and quoted.rb
- selftest and selftest-c pass
- String spec status improves (COMPILE FAIL → CRASH or PASS)

## Notes

- This is a significant refactoring - proceed incrementally
- Commit after each successful phase
- If any phase causes regressions, pause and investigate before proceeding
- Document any limitations or Ruby features we intentionally don't support
