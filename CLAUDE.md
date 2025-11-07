# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## CRITICAL RULE: NEVER EDIT RUBYSPEC FILES

**NEVER EVER EVER EVER edit any files inside the `rubyspec/` directory.**

The RubySpec suite is a test suite that must remain unmodified:
- ❌ **NEVER** edit files in `rubyspec/` to fix failing tests
- ❌ **NEVER** add parentheses or modify test expectations
- ❌ **NEVER** work around compiler bugs by changing the specs
- ❌ **NEVER** modify rubyspec for any reason whatsoever

**If a rubyspec test fails, the ONLY acceptable solution is to fix the compiler implementation, NOT the spec.**

The specs define correct Ruby behavior. If they fail:
- ✅ Fix the implementation in `lib/core/` or compiler code
- ✅ Fix parser precedence bugs
- ✅ Fix operator implementations (like `<<`, `**`, etc.)
- ❌ **NEVER** modify the spec itself

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

## CRITICAL RULE: Documentation Files in docs/ Directory

**NEVER create .md files outside of the docs/ directory unless specifically instructed.**

When creating documentation:
- ✅ Place all .md files in `docs/` directory
- ✅ Use existing documentation files when updating status (e.g., `docs/WORK_STATUS.md`)
- ✅ Keep root directory clean - only `README.md` and `CLAUDE.md` allowed in root
- ❌ **NEVER** create session summaries, bug reports, or investigation files in root
- ❌ **NEVER** create multiple copies of the same documentation

**Exception**: Only `README.md` and `CLAUDE.md` belong in the root directory.

**Why this rule exists:**
- Keeps the repository organized and maintainable
- Makes documentation easy to find in one location
- Prevents clutter in the root directory
- Maintains consistency across sessions

**If you've created .md files in the wrong location:**
1. Move them to `docs/` immediately: `mv FILE.md docs/`
2. Update any references to the moved files
3. Commit the cleanup

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
- `make rubyspec-integer` - Run integer specs (rubyspec/core/integer/)
- `make rubyspec-language` - Run language specs (rubyspec/language/)
- `make spec` - Run custom test cases (spec/ directory)

**Test Hierarchy:**
1. **selftest** - Self-hosting validation (MUST PASS before committing)
2. **selftest-c** - Self-compilation validation (MUST PASS before committing)
3. **rubyspec** - Comprehensive Ruby compatibility tests
4. **spec/** - Reduced test cases and compiler unit tests

**Using spec/ for Development:**
- Create minimal test cases when investigating bugs
- Put tests that use compiler classes directly (not via compiled code)
- Write reduced reproductions that deviate from rubyspec format
- Delete test files once bug is fixed and covered by rubyspec
- Example: `spec/ternary_bug_minimal.rb` for investigating specific bugs

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
- `spec/` - Reduced test cases and compiler unit tests (for development)
- `rubyspec/` - Comprehensive Ruby compatibility test suite (do not edit)
- `mybin/` - Utility scripts
- `docs/` - Architecture documentation and development notes
  - `TODO.md` - Outstanding tasks
  - `KNOWN_ISSUES.md` - Current bugs and limitations
  - `WORK_STATUS.md` - Journaling space for ongoing work
  - `ARCHITECTURE.md` - System architecture
  - `DEBUGGING_GUIDE.md` - Debugging techniques

### Self-Hosting Process
The goal is a three-stage bootstrap:
1. MRI compiles source → `compiler1`
2. `compiler1` compiles source → `compiler2`
3. `compiler2` compiles source → `compiler3` (should equal `compiler2`)

### Docker Environment
Development requires i386 toolchain and specific dependencies managed via Docker. The `ruby-compiler-buildenv` image provides the complete build environment including GCC multilib, Valgrind, and Ruby 2.5.
- Rubyspecs are run with ./run_rubyspec [path to the spec directory or file].