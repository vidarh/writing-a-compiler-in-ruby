# Ruby Compiler TODO

This document tracks known bugs, missing features, and architectural issues that need to be addressed. Items are prioritized: critical bugs first, missing language features second, and architectural improvements third.

## Critical Bugs

- @fixed `make hello` crashes. It worked (though may require running the final
gcc linking step via docker) in commit 9e28ed53b95b3c8b6fd938705fef39f9fa582fef
and failed in subsequent commits. This is critical, as it is a serious
regression. No other bugs should proceed before this has been fixed, but
it is possible other bugs might produce clues as to why this is
broken. - NOTE: This was fixed with a workaround, likely for the
variable lifting bug mentioned below.

### Parser and Compilation Bugs

#### Variable and Scope Issues
- **Variable lifting bug** (`shunting.rb:129`, `compile_calls.rb:18`): `find_vars` doesn't correctly identify variables in some contexts
  **PARTIAL FIX APPLIED** (`transform.rb:279`): Fixed `:call` argument handling by wrapping arguments in array before passing to `find_vars`. This prevents `:callm` nodes from being iterated element-by-element.
  **Status**: 3 out of 4 tests in `spec/variable_lifting.rb` now pass. Common cases like `lambda { puts x + y }` work correctly.
  **Remaining issue**: Blocks with local assignments and nested `:callm` operations still fail. Example: `[1,2,3].each do |n| sum = n + x + y; puts sum end` - first variable `x` stays as local instead of being captured.
  **Investigation notes** (`docs/VARIABLE_LIFTING_DEBUG.md`): Root cause involves interaction between `:call` and `:callm` argument scope handling. The `:callm` handler still adds extra scopes for arguments, and removing this breaks selftest-c.
- **Variable name conflicts** (`regalloc.rb:307`): Variables with names matching method names cause compilation issues
- **Initialization errors** (`parser.rb:120`, `parser.rb:363`): Local variables not properly initialized in some scopes
- @fixed **Member variable assignment** (`parser.rb:20`): Instance variables not explicitly assigned become 0 instead of
nil - (test in spec/ivar.rb confirms this works correctly)
#### Code Generation Bugs
- **Segmentation faults**:
  - `compile_calls.rb:26`: Using 'yield' instead of 'block' causes seg-fault
  - `test/selftest.rb:180`: Inlining certain expressions into method calls causes crashes
  - `compiler.rb:695`: Certain AST traversal patterns trigger segfaults
- **Register allocation issues** (`regalloc.rb:313`): Break statements reset registers incorrectly
- **Method call rewriting** (`compile_calls.rb:314`): callm rewrites trigger unexpected behavior

#### Parser-Specific Bugs
- @fixed **String parsing** (`test/selftest.rb:90`): Character literals require workarounds (27.chr) - now properly handles escape sequences like \e, \t, \n, \r in character literals (test in spec/character_literals.rb confirms fix)
- @fixed **Negative numbers** (`test/selftest.rb:187`): Unary minus operator now properly supported - rewrite_operators in transform.rb now handles prefix :- by converting to method call 0.-() with tagged fixnum zero (test in spec/negative_numbers_simple.rb confirms fix)
- **Expression grouping** (`test/selftest.rb:199`): Certain expressions cause parse/compilation errors
- **Chained method calls on lambdas**: `lambda { x; y }.call` fails with "Missing value in expression" error in shunting yard parser (`treeoutput.rb:92`, `shunting.rb:52`) - works in MRI
- **Comment parsing** (`parser.rb:107`): Specific comment patterns cause parser bugs
- **Whitespace sensitivity** (`lib/core/array.rb:576`, `lib/core/array.rb:670`): Some expressions fail without specific whitespace

#### Code Generation Edge Cases
- **Stack management** (`compiler.rb:622-628`): Issues with local variable stack allocation and `with_local` calls
- **Method dispatch** (`compiler.rb:815`): Array indexing gets incorrectly rewritten
- **Type checking** (`compile_calls.rb:133`): Type enforcement not implemented but mentioned
- **Closure handling** (`compile_calls.rb:286`): Block handling may need rewrite due to variable capture issues

### Runtime Bugs

#### Object Model Issues
- **Hash operations** (`lib/core/hash.rb:62-63`): Equality checks for Deleted objects fail
- **Array operations** (`lib/core/array.rb:1041`): Assignment workaround needed to prevent crashes in selftest
- **String operations** (`lib/core/string.rb:191`): Empty string handling should throw ArgumentError
- @fixed **Global variables** (`test/selftest.rb:23`): Globals appear broken at some point - was generating incorrect assembly with $ prefix, now properly strips prefix and initializes uninitialized globals to nil (test in spec/global_vars.rb confirms fix)

#### Memory Management
- **Garbage collection overhead**: Current GC not optimized for large numbers of small objects
- **Object allocation**: Excessive object creation during compilation
- **String immutability** (`lib/core/string.rb:5`): String objects sort-of immutable causing inefficiencies

## Missing Language Features

### Core Language Constructs

#### Exception Handling
- **Priority: High** - Limited begin/rescue support, no ensure
- **Impact**: Major Ruby programs require exception handling
- **Current state**: Basic infrastructure exists but commented out due to compilation issues
- **Files**: `driver.rb:45-50` (exceptions commented out for bootstrap)

#### Regular Expressions
- **Priority: High** - No regex support at all
- **Impact**: Many Ruby libraries and programs depend on regex
- **Current state**: Not implemented
- **Workaround**: String manipulation methods only

#### Floating Point Arithmetic
- **Priority: Medium** - No float support
- **Impact**: Numeric computations limited to integers
- **Current state**: Not implemented
- **Workaround**: `compiler.rb:130` has temporary hack converting floats to ints

#### Dynamic Code Execution
- **Priority: Medium** - No eval, no runtime code generation
- **Impact**: Limits metaprogramming capabilities
- **Rationale**: Conflicts with ahead-of-time compilation model

### Object Model Features

#### Module System
- **Include mechanism** (`lib/core/array.rb:4`): Module inclusion not fully working
- **Constants access** (`compile_include.rb:48`): Incomplete constant resolution
- **Method precedence** (`compile_include.rb:18`, `compile_include.rb:26`): Superclass vs eigenclass priority unclear

#### Method Features
- **Default arguments**: Limited support
- **Keyword arguments**: Not implemented
- **Method visibility** (`lib/core/symbol.rb:23`): Private/protected not supported
- **Alias and alias_method**: Not implemented
- **undef_method**: Not implemented

#### Metaprogramming
- **const_missing**: Not implemented
- **method_missing**: Basic support exists but incomplete
- **define_method**: Not implemented
- **class_eval/module_eval**: Not implemented

### Standard Library

#### Core Classes Missing Features
- **String**: Comprehensive methods missing (`lib/core/string.rb` has many FIXME items)
- **Array**: Many Enumerable methods missing, inefficient implementations
- **Hash**: Basic functionality only, no advanced features
- **Numeric**: Only basic integer support
- **Symbol**: Incomplete implementation (`lib/core/symbol.rb:53`)

#### Missing Classes
- **File**: Minimal implementation (`lib/core/file.rb`)
- **Dir**: Basic implementation only
- **Time**: Not implemented
- **Thread**: Not implemented
- **Proc**: Basic implementation needs work

## Architectural Issues

### Performance Problems

#### Garbage Collection
- **Issue**: Simple mark-and-sweep collector inefficient for many small objects
- **Impact**: Significant runtime overhead during compilation
- **Solutions needed**:
  - Generational collection
  - Better allocation strategies
  - Object pooling for frequently allocated types

#### Object Allocation
- **Issue**: Excessive object creation during compilation and runtime
- **Impact**: Memory pressure and GC overhead
- **Improvements needed**:
  - Pre-create constants at startup (`compiler.rb:104`)
  - Optimize Proc and environment object allocation (`README.md:32-33`)
  - Better string handling and capacity management

#### Symbol Management
- **Issue**: Symbol table grows without bounds
- **Impact**: Memory usage grows with program size
- **File**: `sym.rb` - no cleanup mechanism

### Code Quality Issues

#### Error Handling
- **Poor error messages**: Many places lack helpful error context
- **Position tracking**: Inconsistent error location reporting
- **Recovery**: Limited error recovery in parser

#### Code Organization
- **Monolithic files**: Some files (especially `compiler.rb`) are very large
- **Circular dependencies**: Bootstrap issues in core library
- **Inconsistent patterns**: Different parts use different coding styles

#### Testing
- **Limited test coverage**: Self-test is minimal
- **No integration tests**: Missing comprehensive language feature tests
- **Manual testing**: Bootstrap process requires manual verification

### Compiler Architecture

#### Static Analysis
- **No optimization passes**: Missing standard compiler optimizations
- **Limited type inference**: Opportunities for better type tracking
- **Dead code**: No dead code elimination at high level

#### Register Allocation
- **Simple allocator**: Current allocator is basic, opportunities for improvement
- **Cross-call preservation**: Register handling across function calls needs work
- **Spilling strategy**: Current spilling strategy is naive

#### Code Generation
- **No inlining**: Method calls always involve full dispatch
- **Poor constant folding**: Limited compile-time evaluation
- **Inefficient patterns**: Some generated assembly patterns suboptimal

## Development Process Issues

### Documentation
- **Limited architecture docs**: Understanding codebase requires extensive exploration
- **Missing API docs**: Many interfaces undocumented
- **Inconsistent comments**: Some areas well-commented, others not

### Build System
- **Docker dependency**: All builds require Docker environment
- **Manual steps**: Some build processes not fully automated
- **Platform specific**: Tied to x86 32-bit, difficult to port

### Debugging
- **Limited debugging tools**: Basic STABS support only
- **Hard to debug generated code**: Assembly debugging challenging
- **Segfault diagnosis**: Difficult to track down runtime crashes

## Priority Assessment

### Must Fix (for basic functionality)
1. Variable lifting and scoping bugs
2. Segmentation faults
3. Exception handling implementation
4. Register allocation issues

### Should Fix (for self-hosting robustness)
1. Parser whitespace sensitivity
2. Memory management improvements
3. Better error reporting
4. Complete object model features

### Nice to Have (for feature completeness)
1. Regular expressions
2. Floating point support
3. Full standard library
4. Advanced optimizations

This TODO list represents the current state of known issues and should be updated as bugs are fixed and new issues discovered.
