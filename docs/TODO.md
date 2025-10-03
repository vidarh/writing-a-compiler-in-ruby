# Ruby Compiler TODO

This document tracks known bugs, missing features, and architectural issues that need to be addressed. Items are prioritized: critical bugs first, missing language features second, and architectural improvements third.

## Critical Bugs

### Parser and Compilation Bugs

#### Variable and Scope Issues
- **Variable name conflicts** (`regalloc.rb:307`): Variables with names matching method names cause compilation issues
- **Initialization errors** (`parser.rb:120`, `parser.rb:363`): Local variables not properly initialized in some scopes
#### Code Generation Bugs
- **Segmentation faults**:
  - `compile_calls.rb:26`: Using 'yield' instead of 'block' causes seg-fault
  - `test/selftest.rb:180`: Inlining certain expressions into method calls causes crashes
  - `compiler.rb:695`: Certain AST traversal patterns trigger segfaults
- **Register allocation issues** (`regalloc.rb:313`): Break statements reset registers incorrectly
- **Method call rewriting** (`compile_calls.rb:314`): callm rewrites trigger unexpected behavior

#### Parser-Specific Bugs
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
  - **Priority: Low** - Missing `Array#map` (alias for collect) and `Array#select` (filter by block)
  - **Impact**: Workarounds needed in compiler code (must use .collect and .reject)
  - **Discovered**: During nested block capture fix (selftest-c revealed method_missing errors)
  - **Note**: Lower priority than fixing nested block parameter capture bug
  - **See**: `docs/NESTED_BLOCK_CAPTURE_DEBUG.md` for details on discovery
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
1. Segmentation faults
2. Exception handling implementation
3. Register allocation issues

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
