# Rescue Spec Compilation Fix - Summary

## Overview
Fixed `rescue_spec.rb` to compile successfully, along with resolving regressions in `defined_spec.rb` and `hash_spec.rb`.

## Status Before Fixes
- **rescue_spec.rb**: COMPILE FAIL
- **defined_spec.rb**: PASS (12 passing tests)
- **hash_spec.rb**: PASS (12 passing tests)
- **pattern_matching_spec.rb**: COMPILE FAIL

## Status After Fixes
- **rescue_spec.rb**: ✅ Compiles successfully
- **defined_spec.rb**: ✅ Compiles successfully (regression fixed)
- **hash_spec.rb**: ✅ Compiles successfully (regression fixed)
- **pattern_matching_spec.rb**: ❌ Still COMPILE FAIL (requires constant-qualified pattern support)

## Changes Made

### 1. Multiple Rescue Clauses Support
**Files**: `compiler.rb`, `parser.rb`

- Added `:rescues` keyword to compiler keyword list
- Implemented `compile_begin_rescues()` to handle `[:rescues, r1, r2, ...]` nodes
- Implemented `build_rescue_conditional()` to generate if/elsif chains that check exception types in order
- Parser creates `[:rescues, ...]` nodes when multiple rescue clauses are present

**Example**:
```ruby
begin
  raise StandardError, "test"
rescue RuntimeError => e
  puts "caught runtime"
rescue StandardError => e
  puts "caught standard"
end
```

### 2. Rescue in Class/Module Bodies
**Files**: `parser.rb`

- Modified `parse_class_body()` to call `parse_rescue_else_ensure()`
- Modified `parse_module_body()` to call `parse_rescue_else_ensure()`
- Wrap rescue/ensure in `:block` nodes when present to match compiler expectations

**Example**:
```ruby
class Foo
  raise "error"
rescue => e
  puts e.message
end
```

### 3. Complex Lvalues in Rescue
**Files**: `parser.rb`, `compiler.rb`

- Changed parser to use `@shunting.parse()` instead of `parse_name` for rescue variables (3 locations)
- Added `:safe_callm` support to `compile_assign()` for safe navigation in assignments
- Modified `compile_begin_rescue()` to only add simple symbols to `let_vars`

**Example**:
```ruby
rescue => self.captured_error
rescue => self&.captured_error
rescue => @ivar
```

### 4. Fixed Regressions

#### defined_spec.rb Regression
**File**: `parser.rb`

**Issue**: `protected :method` in class bodies was not parsing

**Root Cause**: `parse_rescue_else_ensure()` was calling `parse_defexp` which doesn't handle the `protected` keyword

**Fix**: Changed line 450 to call `parse_exp` instead of `parse_defexp`

#### hash_spec.rb Regression
**File**: `treeoutput.rb`

**Issue**: Hash literals with string keys using shorthand syntax (`{"d": 4}`) were failing

**Root Cause**: `convert_ternalt_to_pair()` only handled Symbol keys, not String keys

**Fix**: Added handling for String keys (lines 62-64) to convert them to symbols

## Testing Results

### Selftest Validation
- ✅ `make selftest`: Passes with 0 failures
- ✅ `make selftest-c`: Passes with 0 failures

### Spec Compilation Status
- ✅ `rescue_spec.rb`: Compiles successfully
- ✅ `defined_spec.rb`: Compiles successfully
- ✅ `hash_spec.rb`: Compiles successfully (12 passing tests)

## Files Modified
- `compiler.rb` - Added multiple rescue support
- `parser.rb` - Fixed rescue parsing in classes/modules, complex lvalues
- `treeoutput.rb` - Fixed string key handling in ternalt conversion

## Known Limitations

### pattern_matching_spec.rb
Still fails with constant-qualified patterns like `Hash[a:, b:]` which require Ruby 3.0+ pattern matching parser support. This is beyond the scope of the current fix.

## Implementation Details

### Multiple Rescue Transformation
The compiler transforms multiple rescue clauses into a single rescue that catches all exceptions and uses conditional logic:

```ruby
# Input
begin
  code
rescue Class1 => v1
  body1
rescue Class2 => v2
  body2
end

# Transforms to
begin
  code
rescue => __exc__
  if __exc__.is_a?(Class1)
    v1 = __exc__
    body1
  elsif __exc__.is_a?(Class2)
    v2 = __exc__
    body2
  else
    raise __exc__
  end
end
```

This approach allows the existing single-rescue compilation code to handle multiple rescue clauses without major refactoring.
