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

### 4. Regexp Literals (PARTIAL FIX)
**Error**: Various parsing errors with `/pattern/`
**Fix**: Basic tokenization using @first/@lastop heuristic
**Status**: Works for common cases like `raise_error(ArgumentError, /pattern/)` but needs parser state coordination for full correctness
**Commit**: 039d167
**TODO**: Implement proper parser-tokenizer coordination like `%` handling

## Remaining Issues

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
| exponent_spec | ✓ Compiles, runs | After adding :** support |
| div_spec | ✓ Compiles, runs | Missing methods (runtime) |
| divide_spec | ✗ Fails | Eigenclass compilation |
| downto_spec | ✗ Fails | Register allocation bug |
| fdiv_spec | ✗ Fails | Register allocation bug |
| element_reference_spec | ✗ Fails | Regexp literals (needs full fix) |
| plus_spec | ✗ Fails | Parse infinite loop (unknown cause) |
| pow_spec | ✗ Fails | Syntax error (unknown cause) |

## Progress Summary
- Fixed 4 parsing bugs (negative Float, :%, :*, regexp partial)
- Added 4 stub constants (Float::INFINITY, Float::MAX, Integer::MAX/MIN)
- Fixed run_rubyspec to skip non-spec files
- **5 specs now compile and run**: modulo, coerce, comparison, exponent, div
- 3 specs fail to compile: divide (eigenclass), downto/fdiv (register allocation)
- 3 specs have unresolved parsing issues: element_reference (regexp), plus (infinite loop), pow (syntax error)

## Commits
- ae4a181: Fix negative Float literal parsing
- dbb2cdc: Fix :% symbol parsing
- e8c2cfb: Add :* and :** symbol parsing
- 039d167: Add basic regexp literal tokenization (WIP)
- 6307ad4: Document parsing bug investigation progress
- 5fdfa53: Add Float::INFINITY stub constant
- 3bfbcd4: Add Float::MAX and Integer::MIN/MAX stub constants
- 3df9ba4: Fix run_rubyspec to skip non-spec files

## Next Steps
1. Continue investigating pow_spec and plus_spec parsing issues (complex/time-consuming)
2. Improve regexp tokenization with proper parser state coordination
3. Consider adding Float::INFINITY stub (simple fix per user suggestion)
4. Leave eigenclass and register allocation bugs for later (complex compiler issues)
