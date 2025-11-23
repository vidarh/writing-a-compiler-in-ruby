# Constant Forward Reference and Include Issue

## Problem

The constants_spec.rb and several other specs fail at link time with "undefined reference" errors:

```
undefined reference to `CS_CONST10'
undefined reference to `CS_CONST201'
undefined reference to `PRIVATE_CONSTANT_IN_OBJECT'
```

## Root Cause

The compiler has a mismatch between how constants are registered vs how they're defined:

1. **Registration**: `scan_and_register_constants()` registers ALL constants globally with BARE names
   - Example: Registers `:CS_CONST10` in GlobalScope's @constants

2. **Definition**: Actual compilation creates QUALIFIED symbol names
   - Example: Creates symbol `ConstantSpecs__ModuleA__CS_CONST10`

3. **Reference**: When code references CS_CONST10, GlobalScope finds it in @constants and returns `[:addr, :CS_CONST10]`  - Compiler generates: `movl $CS_CONST10, %eax` (bare symbol)

4. **Link Failure**: Linker can't find bare symbol `CS_CONST10`, only finds `ConstantSpecs__ModuleA__CS_CONST10`

## Why scan_and_register_constants Exists

It solves a forward reference problem in rubyspecs:

```ruby
# Line 39: Define constant in nested module
module ConstantSpecs
  module ModuleA
    CS_CONST10 = :const10_1  # Creates: ConstantSpecs__ModuleA__CS_CONST10
  end
end

# Line 298: Method references CS_CONST10 (compiled before include!)
module ConstantSpecs
  def const10
    CS_CONST10  # ← Compiled before line 326!
  end
end

# Line 326: Include makes CS_CONST10 accessible
include ConstantSpecs::ModuleA  # Includes into Object at runtime
```

Without pre-registration, the method at line 298 wouldn't know CS_CONST10 exists. But the current implementation registers it incorrectly (bare name instead of understanding it will be accessible via include).

## Attempted Fixes

### 1. Don't Register Nested Constants (FAILED)
```ruby
# Only register if depth == 0
if depth == 0
  @global_scope.register_constant(exp[1])
end
```

**Result**: Breaks selftest - `uninitialized constant Keywords`

**Why**: Compiler's own code has constants in classes (e.g., `Compiler::Keywords`) that need registration for forward references.

### 2. Don't Register Any Constants (FAILED)
```ruby
# Comment out entire :assign case in scan_and_register_constants
```

**Result**: Breaks selftest - same Keywords error

## Possible Solutions

###  1. Track Scope Path and Register Qualified Names
Modify `scan_and_register_constants` to track current class/module path and register qualified names:
- Register `:"ConstantSpecs__ModuleA__CS_CONST10"` instead of `:CS_CONST10`
- But this doesn't help lookup - methods still reference bare `CS_CONST10`

### 2. Pre-Process Include Statements
Add `:include` case to `scan_and_register_constants` to simulate includes during pre-scan:
- When encountering `include ModuleA`, add ModuleA's constants to including scope
- Complex because scan phase doesn't have scope objects, just AST

### 3. Generate Runtime Lookups
Change constant references to always use runtime lookup for undefined constants:
- Slower but correct
- Already implemented via `:runtime_const` and `__const_get_global`
- But breaks forward references that scan_and_register_constants was meant to solve

### 4. Register Both Bare and Qualified Names
When defining a constant in a nested scope:
- Create symbol with qualified name (current behavior)
- ALSO create alias with bare name if constant will be accessible via include
- Requires understanding include semantics during code generation

## Current Status

- 34 undefined reference errors in constants_spec.rb alone
- 12 total spec files failing to compile (increased from 10)
- This blocks a significant portion of language specs

## Next Steps

This requires an architectural decision about how the compiler handles constant lookup and forward references. Options:
1. Accept slower runtime lookups for correctness
2. Implement full include pre-processing in scan phase
3. Generate symbol aliases during compilation
4. Redesign constant registration to track qualification

**Priority**: HIGH - blocks multiple rubyspecs and indicates fundamental design issue with constant handling.
