# Fixed Issues Archive

This document archives bugs and issues that have been resolved. Items are kept here for historical reference and to document solutions for similar future problems.

## Critical Bugs (Fixed)

### `make hello` Crash Regression
**Fixed with workaround** - likely related to variable lifting bug below.

The `make hello` target crashed in commits after 9e28ed53b95b3c8b6fd938705fef39f9fa582fef. This was a critical regression that worked previously but started failing. The issue was resolved with a workaround during the variable lifting bug fix.

## Variable and Scope Issues (Fixed)

### Variable Lifting Bug
**Location**: `shunting.rb:129`, `compile_calls.rb:18`
**Problem**: `find_vars` didn't correctly identify variables in some contexts

**Fix** (`transform.rb:254-255, 275-276, 279`): Fixed by wrapping both arguments AND receivers when passing to `find_vars`. This prevents AST nodes from being iterated element-by-element.

**Testing**: All 4 tests in `spec/variable_lifting.rb` pass. All 83 RSpec tests pass. selftest and selftest-c both pass.

**Investigation notes**: See `docs/VARIABLE_LIFTING_DEBUG.md`. Root cause was unwrapped AST nodes being iterated as arrays. Fixed by conditional wrapping: `receiver = n[1].is_a?(Array) ? [n[1]] : n[1]`

### Nested Block Variable Capture Bug
**Problem**: Outer block parameters not correctly captured in nested blocks

**Fix**: See `docs/NESTED_BLOCK_FIX_INVESTIGATION.md` and `docs/NESTED_BLOCK_CAPTURE_DEBUG.md` for complete details.

**Key commits**:
- 654fc39: Initial fix with current_params tracking
- 18fb8ad: Prevent current_params mutation in find_vars
- e04e466, be06b8b, e5cd7fe: Remove all three workarounds

### Member Variable Assignment
**Location**: `parser.rb:20`
**Problem**: Instance variables not explicitly assigned become 0 instead of nil

**Fix**: Instance variables now properly initialize to nil.

**Testing**: Test in `spec/ivar.rb` confirms this works correctly.

## Parser Issues (Fixed)

### String Parsing and Character Literals
**Location**: `test/selftest.rb:90`
**Problem**: Character literals required workarounds (e.g., `27.chr`)

**Fix**: Now properly handles escape sequences like `\e`, `\t`, `\n`, `\r` in character literals.

**Testing**: Test in `spec/character_literals.rb` confirms fix.

### Negative Numbers
**Location**: `test/selftest.rb:187`
**Problem**: Unary minus operator not properly supported

**Fix**: `rewrite_operators` in `transform.rb` now handles prefix `:-` by converting to method call `0.-()` with tagged fixnum zero.

**Testing**: Test in `spec/negative_numbers_simple.rb` confirms fix.

## Runtime Issues (Fixed)

### Global Variables
**Location**: `test/selftest.rb:23`
**Problem**: Global variables appeared broken - was generating incorrect assembly with `$` prefix

**Fix**: Now properly strips prefix and initializes uninitialized globals to nil.

**Testing**: Test in `spec/global_vars.rb` confirms fix.
