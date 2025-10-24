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

## Future Work

To fix rescue across block boundaries:

1. **Option A**: Save/restore exception handler stack when calling blocks
   - Modify Proc#call to preserve @@exc_stack context
   - May require changes to closure compilation

2. **Option B**: Use dynamic handler lookup instead of stack
   - Walk stack frames at raise time to find handlers
   - More complex but more robust

3. **Investigation needed**:
   - How are blocks/closures compiled?
   - Where is the handler stack context lost?
   - Can we pass handler context through closure environment?

## Test Cases

Created test files demonstrating the issues:
- `test_rescue_with_raise.rb` - Works (rescue in simple method)
- `test_chained_rescue.rb` - Crashes (chained call)
- `test_block_rescue_simple.rb` - Doesn't catch (block boundary)
