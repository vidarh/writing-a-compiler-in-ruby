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

## Code Generation Bugs (Fixed)

### Yield Inside Block Segfault
**Location**: `compile_calls.rb:23`
**Problem**: Using `yield` inside a block passed to another method caused segmentation fault. The __closure__ was 0 when yield was called from within a nested block context.

**Fix**: Modified `lib/core/proc.rb` to store @closure instance variable and pass it to the lambda in Proc#call instead of 0. Updated `transform.rb` rewrite_lambda to pass __closure__ to __new_proc. Removed workaround in compile_calls.rb (changed block.call to yield). Also removed :proc and :lambda from compiler.rb @@keywords since they're handled by transformation phase.

**Testing**: Tests in `spec/yield_in_block_segfault.rb` (first two tests pass). Selftest passes.

**Commit**: 4d2af15

**Note**: This fix enables Array#map implementation but exposes a separate bug where top-level lambdas fail when they reference __closure__ (third test in spec documents this).

### Chained Method Calls on Lambdas
**Location**: Parser
**Problem**: Chained method calls on lambda literals didn't work (e.g., `lambda { }.call`)

**Fix**: Removed `:lambda` from keyword list and added conversion in treeoutput.rb to transform `[:call, :lambda, [], [:proc, ...]]` to `[:lambda, ...]`. Lambda now parses like `proc` (as method call with block), allowing method chaining.

**Testing**: Test in `spec/lambda_chained_call.rb` confirms fix.

## Standard Library Features (Fixed)

### Array#map and Array#select
**Location**: `lib/core/array.rb`
**Problem**: Array#map (alias for collect) and Array#select (filter by block) were missing

**Fix**: Implemented Array#map as proper alias using &block parameter forwarding: `def map(&block); collect(&block); end`. Array#select was already implemented. Both methods now work correctly thanks to yield-in-block segfault fix.

**Testing**: All 5 tests in `spec/array_map_select.rb` pass.

**Commit**: 3a16997

## Compiler Workarounds Removed

### Symbol Comparison in emitter.rb
**Location**: `emitter.rb:153` (save_result method)
**Problem**: Symbol comparison `param != :eax` didn't work reliably, required using `param.inspect != ":eax"` workaround

**Fix**: Direct symbol comparison now works correctly. Removed workaround and simplified to `if param != :eax`.

**Testing**: selftest-c passes

**Commit**: 7e3bfa3

### Block Passing and yield Support
**Location**: `emitter.rb:320-343` (with_local and with_stack methods)
**Problem**:
- Couldn't pass block directly to with_stack, required intermediate variable and block.call
- yield didn't work in with_stack, had to use block.call instead

**Fix**: Both issues resolved:
- Can now pass block parameter directly: `with_stack(args+1, &block)`
- Can now use `yield` instead of `block.call`

**Testing**: selftest-c passes

**Commit**: 7e3bfa3

### Redundant movzbl Instruction
**Location**: `emitter.rb:304` (load_indirect8 method)
**Problem**: Second `movzbl(:al,:eax)` instruction included based on GCC output, but purpose unclear

**Fix**: First `movzbl` already zero-extends the byte to eax, second instruction is unnecessary. Removed.

**Testing**: selftest-c passes

**Commit**: 0b26717

### Variable Capture in Block Parameters
**Location**: `compile_calls.rb:40-94` (copy_splat_loop and compile_args_splat_loop methods)
**Problem**: Referring directly to method parameters inside block/lambda caused incorrect variable capture, required creating temporary local variable (e.g., `xindir = indir`)

**Fix**: Variable capture in blocks now works correctly. Can refer directly to parameters inside blocks.

**Testing**: selftest-c passes

**Commits**: 201c57f, 6a3f966

### Array#zip Variable Capture Workaround
**Location**: `lib/core/array.rb:1056` (zip method)
**Problem**: Crash in selftest when using block parameter directly in nested block. Required workaround: `args.collect{|a| b = a; a.to_enum}` instead of `args.collect{|a| a.to_enum}`

**Fix**: Variable capture in nested blocks now works correctly. Can refer directly to block parameters in nested blocks.

**Testing**: selftest-c passes

**Related**: Fixed as part of the same variable capture improvements that fixed compile_calls.rb issues
