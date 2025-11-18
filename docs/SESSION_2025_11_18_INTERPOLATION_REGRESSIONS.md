# Session 2025-11-18: Interpolation Regression Fixes

## Summary

Fixed three regressions introduced by recent string interpolation improvements:
1. **string_spec** - COMPILE FAIL → COMPILES (underscore delimiter + interpolation buffer)
2. **lambda_spec** - COMPILE FAIL → COMPILES (lambda without block return statement)
3. **array_spec** - COMPILE FAIL → COMPILES (%w interpolation handling)

## Bugs Fixed

### 1. String Interpolation Buffer Handling (quoted.rb)

**Issue**: In commit `4f6c6a9` ("Extract string interpolation handling into reusable helper"), I changed `ret << buf` to `ret << buf if buf != ""` in `quoted.rb:82`. This broke selftest-c.

**Root Cause**: The self-compiled compiler relies on empty strings being added to the `[:concat, ...]` array. Skipping empty buffers changed the exact structure.

**Fix**: Changed line 82 back to `ret << buf` (always add buffer, even if empty).

**Commits**:
- f10b0c9: "Fix percent literal parsing and string interpolation bug"

### 2. Lambda Without Block Parsing (shunting.rb)

**Issue**: `lambda { lambda }.should raise_error(ArgumentError)` failed to compile with "Expression did not reduce to single value" error.

**Root Cause**: In `shunting.rb:143-149`, when `lambda` keyword appeared without a block, the code pushed `:lambda` as a value and set `opstate = :infix_or_postfix` but didn't RETURN, causing fall-through to additional processing.

**Fix**: Changed line 148 from `opstate = :infix_or_postfix` to `return :infix_or_postfix`.

**Commits**:
- 3c780f2: "Fix lambda without block parsing in shunting yard"

### 3. %w Word Array Interpolation (tokens.rb)

**Issue**: `%w(a #{3+a} 3)` in array_spec caused "undefined method `split' for [:concat, ...]` error.

**Root Cause**:
- `%w` (lowercase) should NOT interpolate `#{}`  - it should be literal text
- `%W` (uppercase) SHOULD interpolate `#{}`
- Both were handled together in the case statement (lines 559-563)
- When `%W` was used, `needs_interpolation` correctly triggered interpolation, returning `[:concat, ...]` array
- But then `.split` was called on this array, causing the error

**Fix**:
- Separated `%w` from `%W` in case statement (tokens.rb:559-573)
- `%w`: Always split at compile time (no interpolation possible)
- `%W`: Check if content is array (interpolated), call `.split` at runtime; otherwise split at compile time

**Commits**:
- f64e1a5: "Fix %w word array interpolation handling"

## Testing

All fixes verified with:
- ✅ selftest: 0 failures
- ✅ selftest-c: 0 failures
- ✅ string_spec.rb: Compiles successfully
- ✅ lambda_spec.rb: Compiles successfully
- ✅ array_spec.rb: Compiles successfully (was regression)

## Tool Created

**bisect-parse-error.rb**: Binary search tool to find minimal error reproduction
- Takes a file path and error message
- Phase 1: Binary search for first line causing error
- Phase 2: Minimize by removing earlier lines
- Invaluable for reducing complex spec failures to minimal test cases

**Commit**: 1c74ff5: "Add bisect-parse-error.rb tool for finding error sources"

## Key Lessons

1. **ALWAYS verify selftest-c passes before committing** - The self-compiled compiler is more sensitive to subtle behavior changes than MRI Ruby
2. **NEVER revert commits** - Debug the actual issue instead
3. **Even "obvious bug fixes" can break things** - The empty string buffer was intentional for self-compilation
4. **Bisection is powerful** - The bisect tool quickly reduced 300+ line specs to single-line failures
