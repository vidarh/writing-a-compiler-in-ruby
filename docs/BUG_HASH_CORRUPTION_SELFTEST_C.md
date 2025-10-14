# Hash Corruption Bug in selftest-c

## Summary

The self-compiled compiler (`out/driver`) crashes when compiling `test/selftest.rb` with a Hash table corruption that manifests as corrupted arguments to `method_missing`.

## Symptoms

When running `make selftest-c`, the crash occurs at approximately 504,000 GC probes with:

```
===METHOD_MISSING===
sym ptr: 0x2
self ptr: 0x2
```

The backtrace shows:
```
#0  __method_Class_method_missing
#1  __method_Array_hash
#2  __method_Hash__find_slot
```

## Root Cause Analysis

The crash is NOT directly a Hash table corruption. Instead:

1. A vtable thunk tries to call `method_missing` for a missing method
2. The thunk setup calls `__get_symbol` to convert a symbol name
3. `__get_symbol` uses a Hash table to look up symbols
4. This Hash table lookup fails or returns corrupted data (0x2)
5. The corrupted value gets passed as arguments to `method_missing`

The underlying issue is either:
- The Hash table used by `__get_symbol` is corrupted, OR
- The Hash table lookup is failing in some way during `output_functions`

## Minimal Reproducible Test Case

### Files Required

**test_minimal.rb** (empty file):
```ruby
# Empty file
```

**test_reproduce_output_functions.rb**:
```ruby
require 'compiler'

def test_output_functions
  input_source = File.open("test_minimal.rb", "r")
  s = Scanner.new(input_source)
  parser = Parser.new(s, {:norequire => false, :include_paths => ["."]})
  prog = parser.parse

  e = Emitter.new
  c = Compiler.new(e)

  c.setup_global_scope(prog)
  c.rewrite_symbol_constant(prog)
  c.compile_main(prog)

  puts "Reproducing output_functions logic..."

  # Reproduce the logic from output_functions
  c.global_functions.until_empty! do |label, func|
    puts "Processing function: #{label}"
    
    pos = func.body.respond_to?(:position) ? func.body.position : nil
    fname = pos ? pos.filename : nil
    
    c.output_function2(func, label, nil)
  end

  puts "Completed"
end

test_output_functions
exit(0)
```

### Steps to Reproduce

```bash
# Ensure test_minimal.rb is empty
echo "" > test_minimal.rb

# Compile the test with MRI compiler
./compile test_reproduce_output_functions.rb -I . -g

# Run the compiled test
./out/test_reproduce_output_functions
```

### Expected Result

Crash with:
```
===METHOD_MISSING===
sym ptr: 0x2
self ptr: 0x2
```

## Crash Location

The crash occurs while processing the function `__method_Integer___multiply_limb_by_fixnum_with_carry` during `output_functions`.

This is the last function printed before the crash:
```
Processing function: __method_Integer___multiply_limb_by_fixnum_with_carry
```

This corresponds to the method at **lib/core/integer.rb:617** (the `__multiply_limb_by_fixnum_with_carry` method).

## Required Conditions

The crash requires ALL of the following:

1. **Parse with `norequire=false`**: Static require processing must be enabled, which causes all core library files to be parsed and compiled, creating thousands of functions
2. **`c.setup_global_scope(prog)`**: Sets up the global scope
3. **`c.rewrite_symbol_constant(prog)`**: This specific preprocessing step is required
4. **`c.compile_main(prog)`**: Compiles the main function
5. **`c.output_functions`**: Iterates over all compiled functions and outputs them

The crash occurs during step 5, specifically when calling `output_function2` for `__method_Integer___multiply_limb_by_fixnum_with_carry`.

## What Doesn't Cause the Crash

- **`norequire=true`**: No crash (functions are not statically compiled)
- **Skipping `rewrite_symbol_constant`**: Different error (NilClass#each)
- **Skipping `compile_main`**: No crash
- **Skipping `output_functions`**: No crash

## Investigation Notes

### Key Findings

1. The crash occurs at ~504k GC probes consistently
2. The MRI compiler works fine when compiling this test
3. The self-compiled compiler (`out/driver`) crashes when compiling the same test
4. The crash happens during `output_function2` when outputting a specific function
5. The number of functions being processed is very large (thousands from core libraries)

### Related Code Locations

- **output_functions.rb:87**: `def output_functions` - where the iteration happens
- **lib/core/symbol.rb:110**: `def self.__get_symbol(name)` - Hash table lookup for symbols
- **lib/core/symbol.rb:124**: `%s(defun __get_symbol ...)` - Low-level symbol lookup
- **lib/core/integer.rb:617**: `def __multiply_limb_by_fixnum_with_carry` - Function being compiled when crash occurs
- **lib/core/array.rb:646**: `elem_hash = elem_hash & 0xFFFF` - Uses Integer#&

### The Chain of Events

1. `output_functions` iterates over `@global_functions`
2. For each function, it calls `output_function2(func, label, nil)`
3. During compilation of `__method_Integer___multiply_limb_by_fixnum_with_carry`:
   - Some operation requires a vtable lookup
   - The method is not found in the vtable
   - A thunk tries to set up a call to `method_missing`
   - The thunk calls `__get_symbol` to get the symbol name
   - `__get_symbol` performs a Hash table lookup
   - The lookup returns corrupted data (0x2)
   - This corrupted data gets passed to `method_missing`
   - The crash occurs

## Hypothesis

The most likely cause is that the Hash table used by `__get_symbol` for symbol lookups is being corrupted during the massive compilation process. With `norequire=false`, thousands of functions are compiled, and this may trigger a bug in:

- Hash table resizing/rehashing
- Array#hash (which uses Integer#&)
- Integer#& vtable lookup
- Memory allocation or GC interaction

The crash occurs specifically when compiling `__multiply_limb_by_fixnum_with_carry` because this is a complex function with 12 let-bound variables (line 619 of integer.rb), which may stress the Hash table operations more than simpler functions.

## Next Steps

1. Investigate why `__get_symbol`'s Hash table might be corrupted
2. Look at Hash table operations during `output_function2`
3. Check if there are any off-by-one errors or capacity issues in Hash implementation
4. Verify that Integer#& is properly in the vtable for the MRI-compiled compiler
5. Check if Array#hash is functioning correctly during compilation

## Attempted Fixes

### Fix #1: Remove Unnecessary Parentheses (FAILED)

**Date**: 2025-10-14

**Change**: In `lib/core/integer.rb:618`, removed unnecessary outer parentheses around the `let` expression in `__multiply_limb_by_fixnum_with_carry`:

```ruby
# Before:
%s(
  (let (limb_raw fixnum_raw carry_raw low high sum_low sum_high
        result_limb carry_out limb_base low_contribution sign_adjust)
    ...
  )
)

# After:
%s(let (limb_raw fixnum_raw carry_raw low high sum_low sum_high
        result_limb carry_out limb_base low_contribution sign_adjust)
    ...
)
```

**Result**: Bug persists. The crash still occurs at the same location with the same symptoms.

**Conclusion**: The unnecessary parentheses were a code style issue but not the root cause of the Hash corruption.
