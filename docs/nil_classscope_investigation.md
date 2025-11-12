# Nil ClassScope Bug Investigation

## Summary

Classes defined inside lambda/proc scopes fail to compile with error:
```
undefined method `name' for nil:NilClass (NoMethodError) at compile_class.rb:155
```

The root cause: `scope.find_constant(name)` returns nil because the class constant hasn't been registered in the scope chain yet.

## Affected Specs

- **break_spec.rb**: BreakTest2 defined between `it` blocks (line 333)
- **line_spec.rb**: Classes in lambda scopes
- **file_spec.rb**: Classes in lambda scopes
- **singleton_class_spec.rb**: Eigenclass definitions

Total: ~4+ specs blocked by this issue (marked as "nil ClassScope" in TODO.md)

## Minimal Test Case

File: `test_class_in_lambda.rb`
```ruby
l = lambda do
  class Foo
    def test
      42
    end
  end

  Foo.new.test
end

puts l.call
```

**Error**:
```
ERROR: ClassScope is nil for class 'Foo' in scope #<GlobalScope:...>
  Available constants in scope: {...}
```

## Technical Details

### Compilation Flow

1. Parser creates `[:class, :Foo, :Object, [...]]` AST node inside lambda body
2. `compile_class()` is called at compile_class.rb:147
3. Line 149: `cscope = scope.find_constant(name)` searches scope chain for `:Foo`
4. **Problem**: `:Foo` hasn't been registered yet - it's being defined NOW
5. `cscope` is nil
6. Line 155: `cscope.name` crashes with NoMethodError

### Why This Happens

**Static compilation model conflict**:

The compiler uses ClassScope for **static vtable index resolution**. When defining a class:

1. The ClassScope must exist BEFORE compiling the class body
2. This allows static lookup of method offsets for optimization
3. But the class is being DEFINED, so it doesn't exist in the scope yet!

**Top-level classes work** because:
- GlobalScope pre-registers core classes (Object, Class, etc.)
- Top-level class definitions are processed in order
- Each class is added to GlobalScope.constants before compiling its body

**Lambda-scoped classes fail** because:
- Lambda creates a LocalVarScope/FuncScope
- Classes defined inside aren't pre-registered
- `find_constant()` searches up to GlobalScope and finds nothing
- Returns nil → crash

### Why RubySpec Triggers This

RubySpec transforms this:
```ruby
describe "break" do
  it "test 1" do
    # ...
  end

  class BreakTest2  # ← Top-level between it blocks
    # ...
  end

  it "test 2" do
    # uses BreakTest2
  end
end
```

Into this (simplified):
```ruby
lambda do  # describe block becomes lambda
  lambda do # it block
    # ...
  end.call

  class BreakTest2  # ← Now inside outer lambda!
    # ...
  end

  lambda do
    # uses BreakTest2
  end.call
end.call
```

The `class BreakTest2` that was at module top-level is now **inside a lambda scope**.

## Interaction with Vtables

**ClassScope purpose**: Static vtable resolution at compile time

When compiling `obj.method_name`:
1. Look up class of `obj` → get ClassScope
2. Look up `method_name` in ClassScope.vtable → get offset
3. Generate assembly: `call [obj_vtable + offset]`

**The circular dependency**:
- To compile class body, need ClassScope (for vtable lookups)
- To create ClassScope, need to know all methods (to build vtable)
- Can't have one without the other!

**Current workaround for top-level**:
- Two-pass: First collect method names, then compile bodies
- Or: Forward-declare ClassScope, fill vtable incrementally

**Why lambdas break this**:
- Lambda scopes aren't searched for class registration
- No mechanism to forward-declare classes in FuncScope
- `find_constant()` only checks GlobalScope constants

## Potential Solutions

### Option 1: Pre-register classes in parent scope (SIMPLEST)

When parsing `[:class, name, ...]`:
- Immediately create empty ClassScope
- Register in current scope's constants
- Then compile class body

**Pros**: Matches Ruby semantics, minimal changes
**Cons**: Need to handle duplicate definitions

### Option 2: Allow forward references

Make ClassScope nullable during compilation:
- If `cscope` is nil, create placeholder
- Defer vtable resolution to link time
- Fill in vtable entries later

**Pros**: More flexible
**Cons**: Complex, breaks static optimization model

### Option 3: Forbid classes in lambdas

Reject `class` definitions inside lambda/proc scopes

**Pros**: Simple, enforces limitation
**Cons**: Breaks valid Ruby code (used by RubySpec!)

### Option 4: Hoist class definitions

During parsing, move all `class` definitions to enclosing scope

**Pros**: Matches Ruby constant scoping
**Cons**: Complex AST transformation

## Recommended Approach

**Option 1** appears to be the right solution:

1. In parser or transformer, when encountering `[:class, name, ...]`:
   - Create ClassScope for `name` immediately
   - Call `scope.add_constant(name, class_scope)`
   - Continue parsing class body

2. In `compile_class()`:
   - Remove the `scope.find_constant()` lookup
   - ClassScope should already be registered by parser
   - Or: If nil, create it on-demand and register

This matches Ruby's constant definition semantics where the constant becomes available as soon as `class Name` is encountered.

## Files to Modify

- `compile_class.rb:147-159` - Handle nil cscope gracefully
- `parser.rb` or `transform.rb` - Pre-register classes
- `scope.rb` / `globalscope.rb` - Ensure add_constant works for all scope types

## Test Case for Regression

Create `spec/class_in_lambda_spec.rb`:
```ruby
require_relative '../rubyspec/spec_helper'

describe "Class definition" do
  it "allows defining classes inside lambdas" do
    l = lambda do
      class LambdaScopedClass
        def value
          42
        end
      end

      LambdaScopedClass.new.value
    end

    l.call.should == 42
  end

  it "allows classes between lambda calls" do
    define_class = lambda do
      class BetweenLambdas
        def test
          "works"
        end
      end
    end

    use_class = lambda do
      BetweenLambdas.new.test
    end

    define_class.call
    use_class.call.should == "works"
  end
end
```

## References

- **Error location**: compile_class.rb:155
- **Minimal test**: test_class_in_lambda.rb
- **Affected specs**: break_spec.rb, line_spec.rb, file_spec.rb, singleton_class_spec.rb
- **TODO entry**: KNOWN_ISSUES.md #16
