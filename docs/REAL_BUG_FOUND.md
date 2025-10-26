# The Real Bug: Methods with &block Parameters

## Discovery

While investigating why rescue doesn't work across block boundaries, I discovered the **actual bug**: **Methods that take `&block` parameters don't execute correctly**.

## Evidence

### Test Code
```ruby
def run_with_rescue(&block)
  puts "Entered run_with_rescue"  # ❌ NEVER PRINTS
  puts "Before begin"              # ❌ NEVER PRINTS
  begin
    puts "Inside begin"            # ❌ NEVER PRINTS
    block.call
  rescue
    puts "In rescue"
  end
end

run_with_rescue do
  puts "Inside block"              # ✅ PRINTS - block executes!
  raise "error"
end
```

### Actual Output
```
Test 1: Block that raises
Inside block - about to raise      ← Block executes
Unhandled exception: test error    ← But method never ran!
```

### Expected Output
```
Entered run_with_rescue
Before begin
Inside begin
Inside block - about to raise
In rescue
```

## The Bug

When you call a method with a `&block` parameter:
```ruby
def my_method(&block)
  puts "Method called"
  block.call
end

my_method { puts "Block"  }
```

**What happens**: The block executes directly, but the method body NEVER RUNS.

**Result**: Any code in the method (including begin/rescue setup) is skipped.

## Why Rescue Doesn't Work in "Blocks"

It's NOT that rescue doesn't work across block boundaries. It's that:

1. `run_with_rescue(&block)` is called
2. Compiler skips the method body entirely
3. Block executes directly without the surrounding begin/rescue
4. Exception is unhandled because the rescue was never set up

## Test Cases

- `test_method_block_call.rb` - Segfaults when calling method with &block
- `test_block_rescue_simple.rb` - Method body never executes, rescue never set up

## Assembly Evidence

The assembly DOES contain:
- Call to `push_handler`
- Rescue setup code
- All the right instructions

But execution flow never reaches them because the method isn't called correctly.

## This Explains Everything

Why top-level and methods work:
- ✅ Top-level: No &block involved
- ✅ Methods: No &block parameter

Why "blocks" don't work:
- ❌ Methods with &block: The method body never executes

## What Needs to be Fixed

The compiler's handling of methods with `&block` parameters. Specifically, how the method is invoked when a block is passed.

This is NOT an exception handling bug. This is a **method invocation bug** that prevents ANY code in methods with &block from running.
