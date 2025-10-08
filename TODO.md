# TODO - Ruby Compiler

## Critical Parser Issues

### HEREDOC Support (HIGH PRIORITY)
**Status**: NOT IMPLEMENTED - breaks multiple specs

Two-phase implementation plan:

#### Phase 1: Inline HEREDOCs (SIMPLER - DO FIRST)
**Syntax**: `foo(<<HEREDOC\n...\nHEREDOC)`
- Content is inline with the statement
- Can potentially be treated as a token during scanning
- Affects: plus_spec, to_f_spec, and others
- **Approach**: Extend tokenizer to recognize and capture HEREDOC as complete token

#### Phase 2: Deferred HEREDOCs (COMPLEX - DO LATER)  
**Syntax**: `foo(<<HEREDOC)\n...\nHEREDOC`
- Content appears on following lines after the statement
- Requires parser to handle deferred token stream
- Less common in rubyspec tests
- **Approach**: Parser state machine to defer HEREDOC body consumption

**Files to modify**:
- `tokens.rb` - Add HEREDOC token recognition
- `scanner.rb` - Handle HEREDOC body scanning
- `parser.rb` - Process HEREDOC tokens

### Shunting Yard Algorithm Bugs
**Error**: `Syntax error. [{/0 pri=99}]`

**Affected specs**:
- element_reference_spec (integer literal with [])
- exponent_spec
- modulo_spec  
- pow_spec

**Issues**:
- Operator precedence/associativity edge cases
- Token sequence handling in expression parser
- Needs debugging with specific failing cases

**Files to investigate**:
- `shunting.rb` - Core shunting yard algorithm
- `operators.rb` - Operator definitions and precedence

### Block/Lambda Execution Crashes (ARCHITECTURAL)
**Status**: ~12+ specs crash during Proc#call

**Issue**: Deep compiler issue with closure handling
- Blocks/lambdas segfault when executed
- Affects: times_spec, uminus_spec, and many others
- Requires architectural investigation of:
  - Environment capture
  - Closure compilation
  - Block parameter passing

**Files to investigate**:
- `compile_*.rb` - Block/lambda compilation
- `transform.rb` - Block transformations
- Closure handling throughout compiler

## Method Implementations Needed

### Integer Class Methods
- Integer.sqrt - ⚠️ STUB (returns 1) - Newton's method implemented but needs testing
- Integer.try_convert - ⚠️ STUB (basic implementation)

### Fixnum Instance Methods
- gcd/lcm/gcdlcm - ✅ IMPLEMENTED (Euclidean algorithm)
- digits - ✅ IMPLEMENTED (returns digit array)
- ** (exponentiation) - ⚠️ STUB (returns 1)
- << (left shift) - ⚠️ STUB (returns self)
- >> (right shift) - PARTIAL (basic implementation)

### Hash Functionality
- Investigate runtime crash with hash literals
- Ensure Hash#each and other core methods work

### Float Support
- Many Float operations stubbed or missing
- Bignum conversion issues

## Spec Test Categories

### Unfixable (Architecture)
- Block/Lambda crashes: ~12 specs
- Bignum implementation: ~8 specs  
- HEREDOC syntax: ~5 specs (fixable with effort)
- Shunting yard bugs: ~4 specs (fixable with debugging)

### Recently Fixed
- ✅ Unary + operator (abs_spec, magnitude_spec)
- ✅ Tokenizer nil handling
- ✅ Bitwise operators (&, |, ^)
- ✅ Fixnum#times yields index
- ✅ Fixnum#divmod

## Build & Test

### Critical Constraints
- ❗ Never use exceptions in compiler code (breaks self-hosting)
- ❗ Never define top-level methods (breaks compilation)
- ❗ Always run `make selftest && make selftest-c` after changes
- ❗ Use Docker for i386 compatibility

### Test Commands
- `./run_rubyspec rubyspec/core/integer` - Run all Integer specs
- `make selftest` - Self-test suite
- `make selftest-c` - Self-hosting test (critical!)
- `make rspec` - Unit tests
- `make tests` - All tests

## Documentation

Recent docs added:
- `docs/PARSER_FIXES.md` - Parser bug investigation
- `docs/SPEC_SESSION_SUMMARY.md` - Complete spec investigation
- `docs/SPEC_ANALYSIS.md` - Failure categorization
