# Ruby Compiler Architecture

This document provides a comprehensive overview of the Ruby compiler's architecture, design decisions, and implementation details.

## Overview

This is a self-hosting Ruby compiler that compiles Ruby source code to native x86 (32-bit) assembly. The compiler follows a "bottom-up" development approach, prioritizing incremental functionality over completeness. The ultimate goal is a fully self-hosting compiler that can compile itself through a three-stage bootstrap process.

## High-Level Architecture

### Compilation Pipeline

```
Ruby Source → Scanner → Parser → AST → Transformer → Compiler → x86 Assembly → GCC → Native Binary
```

1. **Scanner** (`scanner.rb`): Tokenizes Ruby source into a stream of tokens
2. **Parser** (`parser.rb`): Builds an Abstract Syntax Tree (AST) using recursive descent with Shunting Yard for expressions
3. **Transformer** (`transform.rb`): Applies tree transformations and optimizations
4. **Compiler** (`compiler.rb`): Walks the AST and generates x86 assembly code
5. **Emitter** (`emitter.rb`): Outputs assembly with register allocation and optimization
6. **GCC**: Assembles and links with the garbage collector to produce the final binary

### Bootstrap Process

The compiler achieves self-hosting through a three-stage bootstrap:

1. **Stage 1**: MRI Ruby compiles the compiler source → `out/driver` (native binary)
2. **Stage 2**: `out/driver` compiles the compiler source → `out/driver2`
3. **Stage 3**: `out/driver2` compiles the compiler source → `out/driver3` (should be identical to `driver2`)

## Core Components

### 1. Scanner and Tokenization (`scanner.rb`)

- Character-by-character lexical analysis
- Handles Ruby tokens including keywords, operators, literals
- Position tracking for error reporting
- Special handling for string interpolation and regex patterns

### 2. Parser (`parser.rb`, `parserbase.rb`)

**Parser Architecture:**
- Recursive descent parser for statements and control structures
- Shunting Yard algorithm (`shunting.rb`) for expression parsing with operator precedence
- Handles Ruby's complex grammar including blocks, method calls, and class definitions

**Key Parsing Components:**
- `SEXParser` for S-expression support
- Operator precedence handling (`operators.rb`)
- Error recovery and position tracking
- Support for Ruby's flexible syntax (optional parentheses, etc.)

### 3. Abstract Syntax Tree (`ast.rb`)

- Node-based representation of parsed Ruby code
- Supports all major Ruby constructs: classes, methods, blocks, control flow
- Provides visitor pattern for tree walking
- Enables tree transformations and optimizations

### 4. Code Generation

#### Compiler Core (`compiler.rb`)
- Walks the AST and generates x86 assembly
- Manages scope hierarchies and symbol resolution
- Handles method dispatch and object model implementation
- Coordinates with specialized compilation modules

#### Specialized Compilation Modules
- `compile_arithmetic.rb`: Mathematical operations, integer arithmetic
- `compile_calls.rb`: Method calls, blocks, closures, argument handling
- `compile_class.rb`: Class definitions, inheritance, vtables
- `compile_control.rb`: Control flow (if/while/case/rescue)
- `compile_comparisons.rb`: Comparison operators
- `compile_include.rb`: Module inclusion and mixing

#### Assembly Generation (`emitter.rb`)
- Generates x86 32-bit assembly code
- Integrates register allocation
- Handles calling conventions and stack management
- Supports debugging information (STABS format)
- Peephole optimization

### 5. Register Allocation (`regalloc.rb`)

- Custom register allocator for x86 registers
- Handles register spilling and reloading
- Manages register locking across function call boundaries
- Optimizes register usage for expression evaluation

### 6. Runtime System

#### Object Model
- Vtable-based method dispatch
- Support for eigenclasses and singleton methods
- Implementation of `method_missing`
- Type tagging for integers to reduce object allocation

#### Garbage Collection (`tgc.c`)
- Mark-and-sweep garbage collector written in C
- Integrated with Ruby object allocation
- Handles circular references and finalization
- Currently simple but functional

#### Core Library (`lib/core/`)
- Reimplementation of Ruby core classes for the compiled environment
- Includes: Object, Class, Array, Hash, String, Integer, Symbol
- Handles bootstrapping issues with circular dependencies
- Optimized for the compiled runtime rather than compatibility

### 7. Scope Management

#### Scope Hierarchy (`scope.rb`)
- Base `Scope` class for variable and constant resolution
- Chains scopes to handle nested contexts
- Manages local variable allocation and access

#### Specialized Scopes
- `ClassScope` (`classcope.rb`): Class definitions, instance variables, inheritance
- `LocalVarScope` (`localvarscope.rb`): Method-local variables
- `ControlScope` (`controlscope.rb`): Control flow constructs (blocks, loops)
- `DebugScope` (`debugscope.rb`): Debug information and symbol tables

### 8. Symbol Management (`sym.rb`)

- Global symbol table for method names, constants, and identifiers
- Handles symbol interning and deduplication
- Supports symbol-to-string and string-to-symbol conversion
- Pre-creates commonly used symbols at startup

## Design Decisions and Constraints

### Compilation Model

**Static vs Dynamic Features:**
- `require` statements processed at compile time, not runtime
- Method definitions and class structures mostly static
- Dynamic features like `eval` not supported
- `method_missing` supported through vtable mechanisms

**Memory Management:**
- Objects allocated on heap and managed by garbage collector
- Type tagging for immediate values (integers)
- Stack-allocated local variables where possible
- Reference counting not used due to complexity

### Platform Constraints

**x86 32-bit Target:**
- 4-byte pointers (`PTR_SIZE = 4`)
- Uses x86 calling conventions
- Leverages x86 specific optimizations
- All development done in Docker containers for consistency

**Dependencies:**
- GCC for final assembly and linking
- Docker environment for reproducible builds
- Valgrind for memory debugging

### Language Limitations

**Unsupported Features:**
- Exceptions (begin/rescue/ensure) - minimal support only
- Regular expressions
- Floating point arithmetic
- eval and runtime code generation
- Full metaprogramming (const_missing, etc.)

**Workarounds in Compiler Source:**
- Code marked with `@bug` indicates compiler bug workarounds
- `FIXME` comments mark temporary solutions
- Some Ruby idioms avoided to work around missing features

## Key Data Structures

### AST Nodes
- Expression nodes for operators, method calls, literals
- Statement nodes for control flow, assignments, definitions
- Visitor pattern support for tree traversal

### Value Representation
- `Value` class wraps objects with optional type information
- Supports type tracking through compilation pipeline
- Delegates to underlying Ruby objects for operations

### Register Management
- `Register` class represents x86 registers
- `RegisterAllocator` manages allocation and spilling
- Supports register locking and cross-call preservation

### Function Representation
- `Function` class manages method definitions
- Handles argument parsing and local variable allocation
- Supports blocks and closure creation

## Compilation Phases

### 1. Static Analysis
- Constant folding and dead code elimination
- Variable lifting and scope analysis
- Type inference where possible

### 2. Tree Transformation
- Method call rewriting (e.g., `a.b = c` → `a.b=(c)`)
- Block and closure handling
- Control flow normalization

### 3. Code Generation
- Recursive AST traversal
- Register allocation and stack management
- Method dispatch code generation
- Runtime system integration

### 4. Assembly Optimization
- Peephole optimizations
- Dead code elimination at assembly level
- Register usage optimization

## Testing and Validation

### Self-Test Framework (`test/selftest.rb`)
- Minimal test framework avoiding external dependencies
- Tests core compiler functionality required for self-hosting
- Validates parser, code generation, and runtime behavior

### External Test Suites
- RSpec tests for development
- Cucumber features for behavior validation
- Comparison testing (MRI vs compiled output)

### Bootstrap Validation
- Three-stage bootstrap ensures compiler correctness
- Assembly output comparison between stages
- Functional testing of compiled binaries

## Performance Characteristics

### Current Optimizations
- Type tagging for integers reduces allocation
- Vtable caching for method dispatch
- Pre-allocation of common symbols
- Stack allocation for local variables

### Performance Bottlenecks
- Garbage collection overhead significant
- Large number of small object allocations
- Simple mark-and-sweep collector not optimized for many objects
- No inlining or advanced optimizations

### Scalability Concerns
- Symbol table grows without bounds
- No incremental compilation
- Memory usage grows linearly with program size
- Single-threaded execution model

This architecture represents a functional but evolving compiler design, with many opportunities for optimization and feature completion while maintaining the core goal of self-hosting compilation.