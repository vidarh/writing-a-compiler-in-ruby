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

### 3. :* and :** Symbol Parsing (FIXED)
**Error**: Parse error trying to use ** as operator
**Cause**: sym.rb didn't handle :* or :** symbols
**Fix**: Added :* with lookahead for :**
**Commit**: e8c2cfb

## Remaining Issues

### 4. Regexp Literals (NOT FIXED - complex)
**Status**: Regexp parsing not implemented at all
**Impact**: Any spec with `/pattern/` will fail to compile
**Examples**: element_reference_spec has `/The beginless range for Integer#\[\] results in infinity/`
**Priority**: Lower - can be deferred

### 5. Eigenclass (class << obj) (NOT FIXED - very complex)
**Error**: `undefined method 'klass_size' for #<LocalVarScope>`
**Impact**: divide_spec and other specs with `class << obj` syntax
**Priority**: Leave until last per user instruction

### 6. Register Allocation Error (NOT FIXED - compiler bug)
**Error**: `undefined method 'to_sym' for [:index, :__env__, 2]:AST::Expr` in regalloc.rb:184
**Impact**: downto_spec
**Priority**: Requires compiler internals investigation

## Spec Compilation Status

| Spec | Status | Issue |
|------|--------|-------|
| modulo_spec | ✓ Compiles, runs | be_close not implemented (runtime) |
| coerce_spec | ✓ Compiles, runs | Missing methods (runtime) |
| comparison_spec | ✓ Compiles, runs | Segfaults (runtime) |
| exponent_spec | ✓ Compiles | After adding :** support |
| divide_spec | ✗ Fails | Eigenclass compilation |
| downto_spec | ✗ Fails | Register allocation bug |
| fdiv_spec | ✗ Fails | Register allocation bug |
| element_reference_spec | ✗ Fails | Regexp literals |
| plus_spec | ✗ Fails | Parse error (unknown) |
| pow_spec | ✗ Fails | Syntax error |
| div_spec | ? | Not tested |

## Progress Summary
- Fixed 3 parsing bugs (negative Float, :%, :*)
- 4 specs now compile and run (modulo, coerce, comparison, exponent)
- Remaining failures: eigenclass (complex), register allocation (compiler bug), regexp (not implemented), plus_spec (TBD), pow_spec (TBD)

## Next Steps
1. Investigate pow_spec and plus_spec syntax errors
2. Investigate div_spec
3. Implement minimal regexp tokenization to allow specs to compile
4. Leave eigenclass and register allocation bugs for later
