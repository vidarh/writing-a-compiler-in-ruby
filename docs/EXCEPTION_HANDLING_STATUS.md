# Exception Handling Status - Session 30

## What Works ✅

1. **Top-level rescue blocks**
   ```ruby
   begin
     raise "error"
   rescue
     puts "caught"
   end
   ```

2. **Rescue in regular methods**
   ```ruby
   def test
     begin
       raise "error"
     rescue
       puts "caught"
     end
   end
   ```

3. **Exception propagation within same method**
   - Exceptions raised in begin block are properly caught by rescue in same method

## What Doesn't Work ❌

### 1. Rescue in Methods with Chained Calls
**Symptom**: Immediate segfault during initialization (before any code runs)

```ruby
class Foo
  def bar
    begin
      raise "error"
    rescue
      puts "caught"
    end
  end
end

Foo.new.bar  # ✅ Works - no chain
Foo.new.bar  # ❌ Crashes - chained call
```

**Root cause**: Unknown compiler bug in class/vtable initialization when methods contain rescue blocks

### 2. Rescue Across Block Boundaries
**Symptom**: "Unhandled exception" - rescue block not invoked

```ruby
def run_with_rescue(&block)
  begin
    block.call        # Exception raised here
  rescue
    puts "caught"    # ❌ Never reached!
  end
end

run_with_rescue do
  raise "error"       # Goes straight to "Unhandled exception"
end
```

**Root cause**: Exception handler stack doesn't properly track handlers across block/closure call boundaries

**Impact**: Cannot use rescue to catch exceptions in:
- Test frameworks (describe/it blocks)
- Iterator methods with blocks
- Any method that takes `&block` and calls it

## Technical Details

### Exception Handler Stack
- Handlers are pushed onto `@@exc_stack` in ExceptionRuntime
- `compile_begin_rescue` generates code to push handler
- `compile_unwind` unwinds stack and jumps to handler
- **Problem**: When block.call happens, the exception handler stack context is not preserved correctly across the closure boundary

### Why Top-Level and Simple Methods Work
- Top-level: No function prologue/epilogue complexity
- Simple methods: Handler and raise happen in same stack frame
- **Blocks**: Create new closure/environment, handler stack context is lost

## Workarounds

1. **Avoid rescue in methods with &block parameters**
   - Cannot wrap `block.call` in rescue
   - Must let exceptions propagate

2. **Avoid chained calls to methods with rescue**
   - Store intermediate result: `obj = Foo.new; obj.bar`
   - Don't use: `Foo.new.bar`

## Technical Investigation (Session 30 Continuation)

### What I Discovered

1. **Class variables compile to global variables**:
   - `@@exc_stack` becomes `__classvar__ExceptionRuntime__exc_stack` in assembly
   - These ARE globally accessible and should work across contexts
   - Not a scoping issue

2. **The real problem**: Class methods and blocks don't work together properly
   - Tests with `def self.method` crash with segfaults
   - `ExceptionRuntime.raise(exc)` in kernel.rb calls a class method, but raise is an instance method
   - This somehow works in simple methods but fails across block boundaries

3. **Root cause**: Deep compiler limitation
   - Not just exception handling - affects any use of class methods with blocks
   - Cannot be fixed with simple changes to exception.rb or kernel.rb
   - Requires fixing how the compiler handles class methods and block contexts

### Why Simple Fixes Failed

**Attempt 1**: Convert @@exc_stack to $__exc_stack (global variables)
- Result: Everything crashed, even basic rescue
- Reason: Broke initialization/access patterns

**Attempt 2**: Change ExceptionRuntime.raise to $__exception_runtime.raise
- Result: Still didn't work, "Unhandled exception" in blocks
- Reason: Deeper issue than just the method call

**Attempt 3**: Test class variables across blocks
- Result: Segfault even with simple class method tests
- Reason: Class methods themselves don't work properly in this context

## Future Work

To fix rescue across block boundaries requires fixing fundamental compiler issues:

1. **Fix class method compilation**:
   - Understand why `def self.method` causes segfaults with blocks
   - Fix how class methods are called vs instance methods
   - May require changes to vtable or method resolution

2. **Fix Kernel#raise implementation**:
   - Currently calls `ExceptionRuntime.raise(exc)` (class method)
   - But `raise` is defined as instance method in ExceptionRuntime
   - Need consistent calling convention

3. **Investigation needed**:
   - Why do class methods crash when combined with blocks?
   - How are class methods vs instance methods dispatched?
   - Can we use a different approach that avoids class methods?

4. **Alternative approach**: Redesign exception handling to avoid class methods entirely
   - Use only global variables and functions
   - Implement raise/unwind as s-expression primitives
   - Would require significant refactoring

## Test Cases

Created test files demonstrating the issues:
- `test_rescue_with_raise.rb` - Works (rescue in simple method)
- `test_chained_rescue.rb` - Crashes (chained call)
- `test_block_rescue_simple.rb` - Doesn't catch (block boundary)
