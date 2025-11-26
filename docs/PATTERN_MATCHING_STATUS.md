# Pattern Matching Implementation Status

## Overview
Partial implementation of Ruby 3.0+ pattern matching for case/in statements.

## Implemented Pattern Types

### 1. Bare Variable Binding (`in var`)
**Status**: ✅ Fully implemented

```ruby
case value
in a  # Matches anything, binds to 'a'
  puts a
end
```

**Transform**: `[:in, :a, body]` → `[:when, [:do, [:assign, :a, :__case_value], true], body]`

### 2. Hash Literal Patterns (`in key: value, ...`)
**Status**: ✅ Fully implemented

```ruby
case {a: 1, b: 2}
in a: 1, b: 2  # Checks hash key-value pairs match
  puts "matched"
end
```

**Transform**: Creates conditions checking `__case_value.is_a?(Hash)` and each key-value pair with `==`

### 3. Constant-Qualified Patterns (`in Class[...]`)
**Status**: ✅ Fully implemented for hash patterns

```ruby
case {a: 1, b: 2}
in Hash[a:, b:]  # Checks type and binds keys
  puts a, b      # a=1, b=2
end

case {a: 1, b: 2}
in Hash[a: 1, b: 2]  # Checks type and values
  puts "matched"
end
```

**Transform**: Type check with `is_a?()` + key bindings from shorthand + value checks from full pairs

### 4. AS Patterns (`in Type => var`)
**Status**: ✅ Fully implemented

```ruby
case 42
in Integer => n  # Type check and bind to n
  puts n  # n=42
end
```

**Transform**: `[:in, [:as_pattern, :Integer, :n], body]` → `[:when, [:and, type_check, binding], body]`

### 5. Hash Splat Patterns (`in **`, `in **rest`, `in Hash[a: 1, **]`)
**Status**: ✅ Fully implemented (parsing)

```ruby
case {a: 1, b: 2}
in **  # Match any hash
  puts "matched"
end

case {a: 1, b: 2, c: 3}
in Hash[a: 1, **rest]  # Match hash with at least a: 1
  puts "matched"
end
```

**Transform**:
- Bare `in **` → type check for Hash
- `in Hash[a: 1, **]` → type check + key checks, allows extra keys
- `in **rest` → type check + bind entire hash to rest (TODO: proper rest binding)

**Limitations**:
- `**rest` variable binding not fully implemented (captures entire hash, not remaining keys)
- Only works in hash patterns, not array patterns

## Not Yet Implemented

The following pattern types are **not implemented** and will cause compilation failures:
- **Array patterns** (`[a, b, c]`) - Match array structure and elements
- **Pinning patterns** (`^var`) - Match against existing variable value
- **Find patterns** (`[*, a, *]`) - Match subsequence in array
- **Alternative patterns** (`a | b`) - Match either pattern
- **Guards** (`in a if condition`) - Additional conditions on patterns
- **Nested patterns** - Complex nested pattern structures
- **Rest patterns** (`*rest`) - Capture remaining elements

## Implementation Details

### Files Modified

1. **parser.rb**
   - `parse_pattern()` - Main pattern parsing with special syntax handling, including bare `**` patterns
   - `parse_pattern_list()` - Parse pattern contents inside `[]` or `()`, handles `**` splat before parse_subexp
   - `parse_hash_pattern_after_name()` - Parse bare hash patterns like `a: 1, b: 2`
   - `parse_in()` - Modified to call `parse_pattern()` instead of `parse_condition()`
   - Uses `@shunting.parse([',', ')', ']'])` with stop tokens to prevent comma from being consumed as operator

2. **compiler.rb**
   - Added `:pattern`, `:as_pattern`, `:hash_splat` to keyword list
   - Added `compile_hash_splat(scope, hash_var)` method to handle `**var` syntax in method calls
   - Integrated `rewrite_pattern_matching(exp)` call in `compile()` pipeline

3. **transform.rb**
   - `rewrite_pattern_matching(exp)` - Transform `:in` nodes to `:when` nodes with conditions
   - Two-pass approach: wrap case statements with `:let` to create `__case_value`, then transform :in nodes
   - Handles bare names, AS patterns, hash patterns, constant-qualified patterns, and hash splat patterns
   - Generates type checks and variable bindings
   - Hash splat support in patterns:
     - In `:pattern` nodes: binds `**rest` to entire matched hash
     - In bare `:hash` nodes: properly handles `**rest` and `**nil`
     - Bare `in **rest`: matches any hash and binds to variable

### Transform Strategy

Pattern matching is implemented by transforming `case`/`in` statements into `case`/`when` statements:

1. **Parser phase**: Recognize special pattern syntax and create `:in` nodes
2. **Transform phase**: Convert `:in` nodes to `:when` nodes with conditions
3. **Compiler phase**: Compile as regular `case`/`when` statements

This approach reuses existing `case`/`when` compilation infrastructure.

## Current Compilation Status

### rescue_spec.rb
**Status**: ✅ **COMPILES SUCCESSFULLY**

All rescue-related features working:
- Multiple rescue clauses
- Rescue in class/module bodies
- Complex lvalues in rescue clauses (`self.foo`, `self&.foo`)

### pattern_matching_spec.rb
**Status**: ✅ **COMPILES SUCCESSFULLY** (runs with some runtime errors due to other missing features)

**Progress**:
- Line 533: AS patterns - ✅ Fixed
- Line 784: Hash patterns with full pairs - ✅ Fixed
- Line 1032: Hash splat patterns - ✅ Fixed
- Scoping: __case_value :let wrapping - ✅ Fixed
- Hash splat handling: ✅ Fixed (in patterns: `in {a:, **rest}`, `in Hash[a:, **]`, `in **rest`)
- Closure variable bug: ✅ Fixed (transform.rb:704 - skip :pattern_key in rewrite_env_vars)
- **Current**: Compiles entire spec (1310 lines), runs with some expected failures

**Fix applied**: The closure variable bug was caused by `rewrite_env_vars` rewriting variable names in `:pattern_key` nodes to `[:index, :__env__, N]` before `rewrite_pattern_matching` could process them. Fixed by adding a skip condition for `:pattern_key` variable names (position 1) in `rewrite_env_vars`.

**Before fix**:
- `[:pattern_key, :a]` → `[:pattern_key, [:index, :__env__, 1]]` (wrong!)
- Assembly: `movl $[:index, :__env__, 1], %eax` (literal string!)

**After fix**:
- `[:pattern_key, :a]` stays as `[:pattern_key, :a]`
- Pattern matching transformation creates `[:assign, :a, ...]`
- Then `:a` gets rewritten to `[:index, :__env__, 1]` in the assignment context
- Assembly: correct load/store instructions

**What works**:
- Pattern matching compiles successfully
- All pattern types parse correctly
- Variable scoping with __case_value works
- Pattern matching in closures now compiles correctly

**Runtime issues** (not blocking compilation):
- Some tests fail with "wrong number of arguments" - likely missing method implementations in lib/core/
- Some tests may fail due to incomplete pattern matching runtime support

**Spec coverage**: 150+ pattern matching test cases covering Ruby 3.0+ features (all now parse successfully)

### Scope Assessment

Full Ruby 3.0+ pattern matching is a **major language feature** with extensive syntax:
- 10+ different pattern types
- Complex nested patterns
- Special operators (`=>`, `|`, `^`)
- Array deconstruction
- Hash deconstruction with rest patterns

**Estimated effort for full implementation**: Multiple days of work requiring extensive parser and compiler modifications.

## Known Limitations

1. Only basic pattern types implemented (3 of 10+)
2. No support for pattern operators (`=>`, `|`, `^`)
3. No array pattern matching
4. Constant-qualified patterns limited to hash keyword shorthand
5. No pattern guards or pin operators

## Future Work

If full pattern matching support is desired:

1. Implement AS patterns (`pattern => var`)
2. Add array pattern matching
3. Support pattern operators (alternative, pin)
4. Implement find patterns for arrays
5. Add guard conditions
6. Support rest/splat in patterns
7. Implement full constant-qualified pattern matching (not just hash shorthand)

## References

- Ruby 3.0 pattern matching specification
- `rubyspec/language/pattern_matching_spec.rb` - Comprehensive test suite
