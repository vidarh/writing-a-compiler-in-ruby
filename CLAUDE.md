# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## CRITICAL RULE: Never Revert Without Saving

**NEVER revert code changes during investigation without first saving them.**

When debugging issues:
- ✅ Commit working code before making experimental changes
- ✅ Save changed files to backups: `cp file.rb file.rb.backup`
- ✅ Use `git stash` to temporarily save changes
- ❌ **NEVER** use `git checkout` to revert files during investigation
- ❌ **NEVER** delete files without backing them up first
- ❌ **NEVER** give up and revert - always investigate the actual issue

If code must be reverted:
1. First: `git add <files> && git stash` or `cp <files> <files>.backup`
2. Then: Investigate the actual root cause
3. Only revert as absolute last resort after thorough investigation

## CRITICAL RULE: NEVER Use instance_variable_set/get

**NEVER EVER EVER EVER use `instance_variable_set()` or `instance_variable_get()` in regular Ruby code.**

These methods are **ABOMINATIONS** that should **NEVER** be used:
- ❌ **NEVER** use `obj.instance_variable_set(:@var, value)` - use proper attribute accessors instead
- ❌ **NEVER** use `obj.instance_variable_get(:@var)` - use proper attribute readers instead
- ❌ **NEVER** bypass encapsulation by directly manipulating instance variables from outside
- ❌ **NEVER** use these methods as a "quick fix" or workaround

**There is NEVER a situation in regular Ruby code where you need to call `instance_variable_set` or `instance_variable_get`.**

If you think you need to use these methods, you are approaching the problem incorrectly. Instead:
- ✅ Add proper `attr_accessor`, `attr_reader`, or `attr_writer` declarations
- ✅ Add proper setter/getter methods to the class
- ✅ Refactor the code to use proper encapsulation
- ✅ Pass the value through constructor parameters or method arguments

**Why this rule exists:**
- These methods violate encapsulation and object-oriented design principles
- They make code fragile, hard to understand, and difficult to maintain
- They bypass any validation or logic that should be in setter methods
- They are a code smell indicating poor design

**The ONLY acceptable use** is in metaprogramming frameworks or reflection tools, which this compiler is NOT.

## Project Overview

This is a Ruby compiler written in Ruby that targets x86 assembly. The compiler is designed to bootstrap itself - compile its own source code to native machine code. The project is experimental and self-hosting is achieved with various workarounds for missing functionality.

## Build and Development Commands

### Core Compilation
- `make compiler` - Build the initial compiler (`out/driver`)
- `make compiler-nodebug` - Build without debug symbols
- `./compile <file.rb> -I . -g` - Compile a Ruby file with debug info
- `./compile2 <file.rb> -I . -g` - Use the self-compiled compiler to compile

### Testing
- `make selftest` - Compile and run the self-test suite
- `make selftest-mri` - Run self-test under MRI Ruby (for validation)
- `make selftest-c` - Self-host test (compile with compiled compiler)
- `make rspec` - Run RSpec tests (unit tests for compiler components)
- `make features` - Run Cucumber feature tests (integration tests)
- `make tests` - Run all tests (rspec + features + selftest)

**RSpec Test Types:**
- Unit tests (`spec/*.rb`) - Test individual compiler components (e.g., `spec/compiler.rb`, `spec/function.rb`)
- Compilation tests - Tests that compile Ruby code and verify output (e.g., `spec/ivar.rb`, `spec/global_vars.rb`)
  - Use `CompilationHelper` module for reusable compile-and-run functionality
  - Automatically use Docker for 32-bit assembly and execution
  - Example: `output = compile_and_run(ruby_code_string)`
  - Good for testing language features that may fail if compiler can't compile the test itself

### Docker Environment
- `make buildc` - Build Docker development environment
- `make cli` - Start interactive Docker shell
- All compilation happens inside Docker containers for i386 compatibility

### Debugging
- `make valgrind` - Run selftest under Valgrind
- Use `-g` flag for debug symbols in assembly output
- **See [docs/DEBUGGING_GUIDE.md](docs/DEBUGGING_GUIDE.md) for comprehensive debugging patterns and techniques**

## Architecture

### Core Components

**Driver and Bootstrap Chain:**
- `driver.rb` - Main compiler entry point, coordinates parsing and compilation
- `compiler.rb` - Core compiler class with code generation methods
- Bootstrap sequence: MRI Ruby → `out/driver` → `out/driver2` (self-compiled)

**Parser:**
- `parser.rb` - Main parser using recursive descent with Shunting Yard for expressions
- `parserbase.rb` - Base parser functionality
- `shunting.rb` - Shunting yard expression parser
- `tokens.rb` - Tokenizer/scanner
- `operators.rb` - Operator precedence and definitions

**Code Generation:**
- `compile_*.rb` files - Specialized compilation modules:
  - `compile_calls.rb` - Method calls and function invocation
  - `compile_class.rb` - Class definitions and object model
  - `compile_arithmetic.rb` - Mathematical operations
  - `compile_control.rb` - Control flow (if/while/case)
  - `compile_comparisons.rb` - Comparison operators

**Core Libraries:**
- `lib/core/` - Ruby core class implementations for the compiled environment:
  - `object.rb`, `class.rb` - Object model foundation
  - `array.rb`, `hash.rb`, `string.rb` - Collection types
  - `integer.rb` - Integer implementation with type tagging
- `tgc.c` - Garbage collector implementation (C code)

**Scoping and Symbols:**
- `scope.rb` - Variable scoping management
- `sym.rb` - Symbol table and symbol management
- `ast.rb` - Abstract syntax tree nodes
- `value.rb` - Value representation and tracking

### Compilation Flow

1. **Parse**: `scanner.rb` → `parser.rb` → AST
2. **Transform**: `transform.rb` applies tree transformations
3. **Compile**: `compiler.rb` walks AST generating x86 assembly
4. **Assemble**: GCC assembles and links with garbage collector

### Static Requirements Processing
- `require` statements are processed at compile time, not runtime
- Files are parsed and included during compilation phase
- Include paths managed via `-I` flags

## Key Constraints and Limitations

### Missing Language Features
- **Exceptions**: Limited begin/rescue support (commented out for bootstrap)
- **Regular expressions**: Not implemented
- **Float**: Not implemented
- **eval**: Not supported (ahead-of-time compilation model)

### Compilation Model
- Statically compiled to native x86 (32-bit) code
- `require` evaluated at compile time, not runtime
- Dynamic code generation not supported
- Garbage collection integrated but simple

### Bootstrap Workarounds
- Code marked with `@bug` indicates compiler bug workarounds
- `FIXME` comments mark areas needing improvement
- Some Ruby features avoided in compiler source to work around limitations

## Development Notes

### File Organization
- Root: Core compiler modules and build scripts
- `lib/core/` - Ruby standard library reimplementation
- `out/` - Generated binaries and assembly output
- `test/` - Minimal self-hosted test framework
- `spec/` - RSpec tests
  - `compilation_helper.rb` - Helper module for compilation tests (provides `compile_and_run`)
  - Individual spec files test specific components or features
- `features/` - Cucumber behavior tests
- `mybin/` - Utility scripts
- `docs/` - Architecture documentation and development notes
  - `ARCHITECTURE.md` - Detailed architectural documentation
  - `TODO.md` - Development roadmap and planned improvements

### Self-Hosting Process
The goal is a three-stage bootstrap:
1. MRI compiles source → `compiler1`
2. `compiler1` compiles source → `compiler2`
3. `compiler2` compiles source → `compiler3` (should equal `compiler2`)

### Docker Environment
Development requires i386 toolchain and specific dependencies managed via Docker. The `ruby-compiler-buildenv` image provides the complete build environment including GCC multilib, Valgrind, and Ruby 2.5.
- Rubyspecs are run with ./run_rubyspec [path to the spec directory or file].