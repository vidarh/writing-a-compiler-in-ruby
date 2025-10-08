# Parsing Bugs Investigation

## Fixed Bugs

### 1. Negative Float Literals (FIXED)
**Error**: `Syntax error. [{/0 pri=99}]`
**Cause**: tokens.rb line 293 used `Int.expect` instead of `Number.expect` for negative numbers
**Fix**: Changed to `Number.expect` to handle decimal points
**Commit**: ae4a181

### 2. :% Symbol Parsing (FIXED)
**Error**: `Syntax error. [{/0 pri=99}]`
**Cause**: sym.rb checked for operator symbols AFTER `Quoted.expect`, which interpreted `%` as starting a string literal (`%w`, `%q`, etc.)
**Fix**: Moved all operator symbol checks before `Quoted.expect`
**Commit**: dbb2cdc

## Remaining Issues

### 3. Regexp Literals (NOT FIXED - complex)
**Status**: Regexp parsing not implemented at all
**Impact**: Any spec with `/pattern/` will fail to compile
**Examples**: element_reference_spec has `/The beginless range for Integer#\[\] results in infinity/`
**Priority**: Lower - can be deferred

### 4. Eigenclass (class << obj) (NOT FIXED - very complex)
**Error**: `undefined method 'klass_size' for #<LocalVarScope>`
**Impact**: divide_spec and other specs with `class << obj` syntax
**Priority**: Leave until last per user instruction

### 5. Register Allocation Error (NOT FIXED - compiler bug)
**Error**: `undefined method 'to_sym' for [:index, :__env__, 2]:AST::Expr` in regalloc.rb:184
**Impact**: downto_spec
**Priority**: Requires compiler internals investigation

## Spec Compilation Status

| Spec | Status | Issue |
|------|--------|-------|
| modulo_spec | Compiles, runs | be_close not implemented (runtime) |
| coerce_spec | Compiles, runs | Missing methods (runtime) |
| divide_spec | Fails | Eigenclass compilation |
| downto_spec | Fails | Register allocation bug |
| element_reference_spec | Fails | Regexp literals |
| exponent_spec | ? | Not tested |
| fdiv_spec | ? | Not tested |
| plus_spec | ? | Not tested |
| pow_spec | ? | Not tested |
| comparison_spec | ? | Not tested |
| div_spec | ? | Not tested |

## Next Steps
1. Test remaining specs to categorize failures
2. Fix any additional simple parsing bugs found
3. Leave regexp and eigenclass for later
