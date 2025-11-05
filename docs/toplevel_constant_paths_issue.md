# Toplevel Constant Paths Issue (11b8c88)

## Problem

Commit 11b8c88 "Add support for toplevel constant paths in class/module definitions" breaks selftest-c compilation. The compiled compiler segfaults when trying to compile selftest.rb.

## Original Change

The commit added support for `class ::ClassName` and `module ::ModuleName` syntax which refers to toplevel constants:

### Parser Changes (parser.rb)
- Added check for `::` prefix before parsing class/module names
- Creates `[:toplevel, name]` AST node for absolute constant references
- Handles paths like `::A::B::C`

### Transform Changes (transform.rb)
- `build_class_scopes_for_class`: Handles `[:toplevel, name]` by setting scope to `@global_scope`
- Extracts constant name from the node

### Compilation Changes (compile_class.rb)
- Look up `[:toplevel, name]` constants in `@global_scope`
- Avoids "Unable to find class scope" errors

### Operator Changes (operators.rb)
- Made `::` context-sensitive (prefix for toplevel, infix for namespace resolution)
```ruby
"::" => {
  :infix_or_postfix => Oper.new(100, :deref,    :infix, 2,2,:left),
  :prefix           => Oper.new(100, :toplevel, :prefix)
}
```

## Why It's Needed

RubySpec tests frequently use `class ::Object` to reopen Object at the top level without interference from local constants:

```ruby
# In a spec that defines a local Object class
class Object; end  # Local to the spec

# Need to refer to toplevel Object
class ::Object     # Refers to real Object, not local one
  # Add methods here
end
```

Without this feature, specs fail with:
- "Unable to find class scope for [:sexp, :__S___3aObject]"
- Incorrect constant resolution when specs have nested contexts

## Why It Breaks selftest-c

Timeline of failure:
- `make compiler` - SUCCEEDS (MRI compiles the compiler)
- `make selftest` - SUCCEEDS (compiled compiler runs selftest.rb)
- `make selftest-c` - SEGFAULTS (compiled compiler tries to compile selftest.rb)

The segfault occurs around `__cnt: 632000` during the self-compilation phase.

## Testing Methodology

### Baseline (Working) - f1f871f
```bash
git checkout f1f871f
git checkout cc2c08b -- shunting.rb  # Apply shunting fix
rm -f out/driver* && make compiler
make selftest-c
# Result: PASSES (DONE, Fails: 1)
```

### With Feature - 11b8c88
```bash
git checkout 11b8c88
git checkout cc2c08b -- shunting.rb  # Apply shunting fix
rm -f out/driver* && make compiler
make selftest-c
# Result: SEGFAULT at __cnt: 632000
```

## Root Cause Hypothesis

The issue is likely in one of these areas:

1. **Operator precedence issue:** The prefix `::` operator may interact poorly with existing parsing logic when compiled

2. **Scope resolution bug:** The `@global_scope` lookups or constant path resolution may have a bug that only manifests in compiled code

3. **AST transformation issue:** The `[:toplevel, name]` nodes may not be handled correctly during compilation when the compiler compiles itself

4. **Context-sensitive operator issue:** The dual-mode `::` operator may confuse the compiled parser's state tracking

## Attempted Revert

Attempted to revert 11b8c88 at master but encountered merge conflicts in:
- `docs/language_spec_failures.txt`
- `rubyspec_helper.rb`

These conflicts are due to subsequent commits that depend on or modify related code.

## Files Affected

- `parser.rb` - Parsing of `::` prefix and class/module definitions
- `transform.rb` - `build_class_scopes_for_class` method
- `compile_class.rb` - Constant lookup logic
- `operators.rb` - `::` operator definition
- `docs/language_spec_failures.txt` - Updated spec status
- `rubyspec_helper.rb` - May contain constants affected by feature

## Specs That Need This

From commit message:
- `alias_spec.rb`
- `BEGIN_spec.rb`
- `magic_comment_spec.rb`
- `predefined/toplevel_binding_spec.rb`
- `regexp/grouping_spec.rb`
- `regexp/repetition_spec.rb`

And many others that use `class ::Object` or `module ::Kernel` patterns.

## Next Steps to Fix

1. **Isolate the breaking change:**
   - Test each part of the commit separately:
     - Parser changes only
     - Transform changes only
     - Compile changes only
     - Operator changes only
   - Identify which specific change causes the segfault

2. **Create minimal test case:**
   - Find the smallest Ruby program that triggers the segfault
   - Test if it's related to specific constant names or patterns
   - Check if it's specific to class definitions or also affects general constant access

3. **Debug the compiled compiler:**
   - Use gdb to find exact location of segfault
   - Check if it's during parsing, transformation, or compilation phase
   - Look for infinite loops or stack overflows

4. **Alternative implementations:**
   - Implement toplevel constant access without modifying `::` operator
   - Use a different AST representation
   - Handle `::` prefix at a different compilation stage

5. **Incremental approach:**
   - Start by supporting `::Constant` in expressions (not class definitions)
   - Add class/module support separately
   - Test selftest-c after each increment

## Related Issues

This may be related to other constant path handling code in:
- Commit a4781f2 "Add support for constant paths in class/module definitions"
- Commit 1973e93 "Improve constant path handling in transformer and compiler"

These earlier commits added `A::B::C` support and may have introduced complexity that interacts poorly with the `::` prefix feature.
