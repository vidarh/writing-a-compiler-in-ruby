# Exception Handling Implementation Proposal

## Executive Summary

Implement Ruby exception handling (raise/rescue/ensure) using a **separate exception stack** approach, **100% self-hosted in Ruby**. Exception handlers save stack state (%ebp, %esp, rescue label address) in Ruby objects, similar to how Proc saves function pointers. Raising an exception restores the saved stack state and jumps to the rescue handler using pure Ruby + s-expression assembly. **NO C CODE REQUIRED** - this is a completely self-hosting implementation.

---

## Implementation Language Strategy

### CRITICAL CONSTRAINT

**Using C code for exception handling is TOTALLY INEXCUSABLE and UNACCEPTABLE under ALL circumstances.**

The compiler is self-hosting. Exception handling MUST be implemented in Ruby that the compiler can compile. This is a non-negotiable architectural principle.

---

### 100% Self-Hosted Implementation

**Primary Language: Ruby** (in `lib/core/exception.rb`)
- Exception stack management (using class variables @@exc_stack)
- Exception object implementation (enhanced Exception classes)
- Handler registration and lookup
- Exception matching logic
- Stack unwinding (restoring %ebp, %esp, jumping to rescue label)

**S-expression Syntax** (via `%s()` in Ruby code)
- Saving/restoring stack frame (%ebp, %esp) - NO setjmp/longjmp needed!
- Computing label addresses for rescue handlers
- Direct register manipulation for stack unwinding
- Jumping to rescue handlers

**Key Insight from Proc/preturn Implementation**:

The compiler already has mechanisms for non-local control flow:
- `Proc#call` stores function addresses in Ruby objects
- `:stackframe` evaluates to %ebp (current stack frame pointer)
- `preturn` restores saved %ebp and returns from Proc

Exception handlers work similarly:
- Save %ebp (stack frame pointer) using `:stackframe`
- Save %esp (stack pointer) using inline assembly `%s()`
- Save rescue handler label address (like Proc stores @addr)
- On raise: restore %ebp/%esp, jump to saved address
- **No C code required** - pure Ruby + s-expressions!

---

## Current State Analysis

### What Already Exists

1. **Exception Classes** (`lib/core/exception.rb`)
   - Basic exception hierarchy defined but empty
   - Classes: Exception, StandardError, TypeError, NoMethodError, ArgumentError, etc.
   - No instance variables, no `message` or `backtrace` support

2. **Parser Support** (`parser.rb:179-203`)
   - `parse_rescue` - handles `rescue ExceptionClass => var` syntax
   - `parse_begin` - handles `begin...rescue...end` blocks
   - Returns AST nodes: `[:rescue, class, var, body]`, `[:block, [], exps, rescue_]`

3. **Compiler Stub** (`compiler.rb:313-316`)
   - `compile_rescue(scope, rval, lval)` - currently just warns and compiles lval
   - No implementation, just a placeholder

4. **Infrastructure**
   - Standard function preamble/postamble in place (`emitter.rb:606-658`)
   - Stack frame structure well-defined with %ebp/%esp

### What's Missing

- Exception object instantiation with message and backtrace
- Exception stack to track rescue handlers
- raise/rescue/ensure compilation
- Stack unwinding mechanism
- Backtrace capture and formatting
- Re-raise support (bare `raise` in rescue block)

---

## Design: Separate Exception Stack

### Core Concept

Maintain a **global exception handler stack** separate from the call stack. Each `begin...rescue` block pushes a handler onto this stack, and `raise` uses this stack to find the appropriate handler and unwind.

### Why Separate Stack?

1. **Orthogonal Design**: Exception handling doesn't pollute normal function calls
2. **Performance**: Zero overhead on non-exceptional code paths
3. **Simplicity**: No need to modify every function preamble/postamble
4. **Compatibility**: Works with existing GC, closures, and calling conventions
5. **Debuggability**: Clear separation between control flow and exception flow

---

## Architecture Components

### 1. Exception Handler (Pure Ruby)

Add to `lib/core/exception.rb`:

```ruby
# Exception handler structure
# Stores saved stack state for unwinding
# Similar to how Proc stores function address/environment
class ExceptionHandler
  def initialize
    @saved_ebp = nil      # Saved stack frame pointer
    @saved_esp = nil      # Saved stack pointer
    @handler_addr = nil   # Address of rescue label to jump to
    @rescue_classes = nil # nil = catch all, or Array of classes to catch
    @next = nil           # Next handler in chain
  end

  # Save current stack state
  # Called when setting up begin...rescue
  # handler_addr is the address of the rescue: label (computed by compiler)
  def save_stack_state(handler_addr)
    @handler_addr = handler_addr
    # Save current frame pointer
    %s(assign @saved_ebp (stackframe))
    # Save current stack pointer
    %s(assign @saved_esp (reg esp))
  end

  def saved_ebp
    @saved_ebp
  end

  def saved_esp
    @saved_esp
  end

  def handler_addr
    @handler_addr
  end

  def rescue_classes
    @rescue_classes
  end

  def rescue_classes=(classes)
    @rescue_classes = classes
  end

  def next
    @next
  end

  def next=(n)
    @next = n
  end
end

# Exception runtime - manages the exception handler stack
# This is a singleton-like class (using class variables)
class ExceptionRuntime
  # Global exception state
  @@exc_stack = nil           # Top of handler stack
  @@current_exception = nil   # Currently raised exception object

  # Push a handler onto the exception stack
  # Returns the handler for caller to initialize
  def self.push_handler(rescue_classes = nil)
    handler = ExceptionHandler.new
    handler.rescue_classes = rescue_classes
    handler.next = @@exc_stack
    @@exc_stack = handler
    return handler
  end

  # Pop handler from stack
  def self.pop_handler
    if @@exc_stack
      @@exc_stack = @@exc_stack.next
    end
  end

  # Get current handler
  def self.current_handler
    @@exc_stack
  end

  # Raise an exception
  # Unwinds stack by restoring saved %ebp/%esp and jumping to handler
  def self.raise(exception_obj)
    @@current_exception = exception_obj

    if @@exc_stack
      handler = @@exc_stack
      @@exc_stack = handler.next  # Pop before jumping

      # TODO: Check if exception matches rescue classes

      # Restore stack state and jump to rescue handler
      # This is like preturn but jumps to arbitrary label instead of returning
      %s(do
        (assign ebp (callm handler saved_ebp))      # Restore frame pointer
        (assign esp (callm handler saved_esp))      # Restore stack pointer
        (assign ebx (index ebp -4))                 # Restore numargs
        (jmp (callm handler handler_addr))          # Jump to rescue: label
      )
      # Never returns
    else
      # Unhandled exception
      %s(printf "Unhandled exception: ")
      msg = exception_obj.to_s
      %s(printf "%s\n" (callm msg __get_raw))
      %s(exit 1)
    end
  end

  # Get current exception (called from rescue block)
  def self.current_exception
    @@current_exception
  end

  # Clear current exception (after rescue handles it)
  def self.clear
    @@current_exception = nil
  end
end
```

**Key Implementation Details**:

1. **No C code** - Uses `%s()` for low-level operations
2. **`:stackframe`** - Special s-expression that evaluates to %ebp
3. **`(reg esp)`** - Access %esp register directly
4. **`(jmp addr)`** - Jump to saved handler address
5. **Similar to Proc** - Stores addresses/state in Ruby object
6. **Similar to preturn** - Restores %ebp/%esp for stack unwinding

### 2. Exception Objects (Ruby)

Enhance `lib/core/exception.rb`:

```ruby
class Exception
  attr_reader :message, :backtrace

  def initialize(msg = nil)
    @message = msg
    @backtrace = nil  # TODO: capture backtrace
  end

  def to_s
    @message || self.class.to_s
  end

  def inspect
    "#<#{self.class}: #{@message}>"
  end
end

class StandardError < Exception
end

class RuntimeError < StandardError
  def initialize(msg = "RuntimeError")
    super(msg)
  end
end

# ... other exception classes with proper initialize
```

### 3. Compiler Changes

#### 3.1 `compile_begin` - Handle begin...rescue...end

**Pure Ruby approach** - the compiler generates Ruby code that calls ExceptionRuntime:

```ruby
def compile_begin(scope, exps, rescue_clause)
  rescue_label = @e.get_local    # Label for rescue handler
  after_label = @e.get_local     # Label after rescue

  if rescue_clause
    rescue_class = rescue_clause[1]
    rescue_var = rescue_clause[2]
    rescue_body = rescue_clause[3]

    # Generate code that:
    # 1. Pushes handler onto exception stack
    # 2. Saves stack state (ebp, esp, rescue_label address)
    # 3. Executes try block
    # 4. On normal completion: pops handler
    # 5. On exception: jumps to rescue_label (via ExceptionRuntime.raise)

    # Push handler
    # handler = ExceptionRuntime.push_handler(rescue_class)
    compile_eval_arg(scope,
      [:assign, :__handler,
        [:callm, :ExceptionRuntime, :push_handler, [rescue_class]]])

    # Save stack state into handler
    # handler.save_stack_state(address_of rescue_label)
    # The compiler computes the address of rescue_label
    compile_eval_arg(scope,
      [:callm, :__handler, :save_stack_state, [[:addr, rescue_label]]])

    # Compile try block
    compile_do(scope, exps)

    # Normal completion - pop handler
    compile_eval_arg(scope, [:callm, :ExceptionRuntime, :pop_handler])
    @e.jmp(after_label)

    # Rescue handler (jumped to by ExceptionRuntime.raise)
    @e.label(rescue_label)

    # Get exception from ExceptionRuntime
    compile_eval_arg(scope,
      [:assign, :__exc, [:callm, :ExceptionRuntime, :current_exception]])

    # Bind to rescue variable if specified
    if rescue_var
      compile_assign(scope, rescue_var, :__exc)
    end

    # Compile rescue body
    compile_do(scope, rescue_body)

    # Clear exception
    compile_eval_arg(scope, [:callm, :ExceptionRuntime, :clear])

    @e.label(after_label)
  else
    # No rescue - just compile body
    compile_do(scope, exps)
  end
end
```

**Key Points**:
- Generates **Ruby method calls** to ExceptionRuntime (not C calls)
- Uses `[:addr, label]` s-expression to get label address (like Proc stores function addresses)
- rescue_label is where execution resumes when exception is raised
- **100% self-hosted** - all code is Ruby that the compiler compiles

#### 3.2 `compile_raise` - Raise Exception

**Pure Ruby** - just call ExceptionRuntime.raise:

```ruby
def compile_raise(scope, exception_or_message = nil)
  if exception_or_message.nil?
    # Bare raise - re-raise current exception
    compile_eval_arg(scope,
      [:callm, :ExceptionRuntime, :raise,
        [[:callm, :ExceptionRuntime, :current_exception]]])
  else
    # Create exception object based on argument type
    # This logic can be in a Ruby helper method
    exception_expr = case exception_or_message
    when String
      [:callm, :RuntimeError, :new, [exception_or_message]]
    else
      # Assume it's an exception class or object
      # TODO: Add type checking/conversion
      exception_or_message
    end

    # Raise the exception
    compile_eval_arg(scope,
      [:callm, :ExceptionRuntime, :raise, [exception_expr]])
  end

  # Mark as non-returning for dead code analysis
  Value.new([:subexpr])
end
```

**Simpler approach**: Implement `Kernel#raise` in Ruby, compiler just generates call to it:

```ruby
# In lib/core/kernel.rb
module Kernel
  def raise(exception_or_msg = nil)
    exc = case exception_or_msg
    when nil
      ExceptionRuntime.current_exception
    when String
      RuntimeError.new(exception_or_msg)
    when Class
      exception_or_msg.new
    else
      exception_or_msg  # Already an exception object
    end

    ExceptionRuntime.raise(exc)
    # Never returns
  end
end
```

Then compiler just does:
```ruby
def compile_raise(scope, arg = nil)
  compile_eval_arg(scope, [:call, :raise, [arg]])
end
```

**100% Ruby, zero C code!**

#### 3.3 `compile_ensure` - Ensure Blocks

Ensure is trickier - must run even during exception unwinding:

```ruby
def compile_ensure(scope, try_block, ensure_block)
  # Use separate flag to track if exception is in flight
  # Ensure block runs regardless, then re-raises if needed

  exception_flag_label = @e.get_local
  after_label = @e.get_local

  # Local variable to track exception state
  @e.pushl(0)  # 0 = no exception, 1 = exception in flight

  # ... compile begin/rescue with ensure awareness ...

  # Always run ensure block
  compile_do(scope, ensure_block)

  # Check if exception was in flight
  @e.popl(:eax)
  @e.cmpl(1, :eax)
  @e.jne(after_label)

  # Re-raise exception
  @e.call(:__exc_current)
  @e.pushl(:eax)
  @e.call(:__exc_raise)

  @e.label(after_label)
end
```

### 4. Integration Points

#### 4.1 Parser Integration

- `parse_begin` already works, returns `[:block, [], exps, rescue_clause]`
- Need to handle `ensure` - currently not parsed
- Add `parse_ensure` to parser.rb

#### 4.2 Transform Phase

- No changes needed to `transform.rb`
- Exception handling is orthogonal to let/closure rewriting

#### 4.3 Standard Library

Need to implement:
- `Kernel#raise` (alias `fail`)
- Exception class hierarchy with `#initialize`, `#message`, `#backtrace`
- Backtrace capture (can start with stub returning empty array)

---

## Implementation Phases

### Phase 1: Basic raise/rescue (1-2 days)

**Goal**: Simple raise with string, rescue all

1. Add exception stack runtime (`exc.c`)
   - `__exc_push_handler`, `__exc_pop_handler`, `__exc_raise`, `__exc_current`, `__exc_clear`
   - Global `__exc_stack` and `__current_exception`

2. Implement `compile_begin` for basic rescue
   - No class matching, catch all exceptions
   - No rescue variable binding yet

3. Implement `compile_raise` for string messages
   - Auto-wrap in RuntimeError

4. Test with simple examples:
   ```ruby
   begin
     raise "error"
   rescue
     puts "caught"
   end
   ```

**Deliverable**: Basic raise/rescue works, selftest still passes

### Phase 2: Exception classes and variables (1-2 days)

**Goal**: Typed rescue with variable binding

1. Enhance Exception classes
   - Add `@message` instance variable
   - Add `#initialize(msg)`, `#to_s`, `#inspect`

2. Implement exception class matching in rescue
   - Check exception object's class against rescue class
   - Use vtable/class comparison

3. Implement rescue variable binding
   - `rescue TypeError => e` assigns exception to `e`

4. Add `Kernel#raise` method
   - Handle `raise ExceptionClass`, `raise ExceptionClass, "msg"`, `raise exception_object`
   - Handle bare `raise` (re-raise)

**Deliverable**: Typed rescue works, can catch specific exception classes

### Phase 3: Multiple rescue clauses (1 day)

**Goal**: Multiple rescue handlers per begin block

1. Extend `parse_begin` to handle multiple rescue clauses
   - Currently only handles one

2. Compile multiple rescue checks
   - Try each rescue class in order
   - Fall through to next if no match

3. Test with:
   ```ruby
   begin
     raise TypeError
   rescue ArgumentError
     puts "arg error"
   rescue TypeError
     puts "type error"
   end
   ```

**Deliverable**: Multiple rescue clauses work correctly

### Phase 4: Ensure blocks (1-2 days)

**Goal**: Ensure blocks run regardless of exception

1. Add `parse_ensure` to parser
   - `begin...rescue...ensure...end` syntax

2. Implement `compile_ensure`
   - Track exception-in-flight flag
   - Always run ensure block
   - Re-raise if exception was in flight

3. Test ensure runs in all paths:
   - Normal completion
   - Exception caught by rescue
   - Exception not caught (unwinds)

**Deliverable**: Ensure blocks work in all cases

### Phase 5: Backtrace support (2-3 days)

**Goal**: Capture and display backtraces

1. Add backtrace capture mechanism
   - Walk stack frames via %ebp chain
   - Use debug symbols to map addresses to function names
   - Store in Exception object

2. Implement `Exception#backtrace`
   - Return array of strings: `["file.rb:line:in `method'", ...]`

3. Add backtrace printing for unhandled exceptions

**Deliverable**: Exceptions have useful backtraces

### Phase 6: Edge cases and optimization (1-2 days)

**Goal**: Handle corner cases, optimize

1. Nested exception handling
2. Exceptions in rescue blocks
3. Exceptions in ensure blocks
4. Return/break/next during exception handling
5. Performance optimization (minimize stack manipulation)

**Deliverable**: Robust exception handling, all edge cases covered

---

## Testing Strategy

### Unit Tests

Create `test/test_exceptions.rb`:

```ruby
# Phase 1
def test_basic_raise_rescue
  begin
    raise "error"
    return :fail
  rescue
    return :ok
  end
end
puts test_basic_raise_rescue  # => :ok

# Phase 2
def test_typed_rescue
  begin
    raise TypeError
  rescue ArgumentError
    return :wrong
  rescue TypeError
    return :ok
  end
end
puts test_typed_rescue  # => :ok

# Phase 3
def test_rescue_variable
  begin
    raise TypeError, "my message"
  rescue TypeError => e
    return e.message
  end
end
puts test_rescue_variable  # => "my message"

# Phase 4
def test_ensure
  x = 0
  begin
    raise "error"
  rescue
    x = 1
  ensure
    x = 2
  end
  return x
end
puts test_ensure  # => 2
```

### Integration with Rubyspec

Many specs currently skip exception tests. After implementation:
- Remove skips from rescue_spec.rb, ensure_spec.rb
- Test exception handling in various contexts
- Validate against MRI behavior

---

## Performance Considerations

### Normal Case (No Exception)

- **Zero overhead**: No exception handling code runs unless exception is raised
- Handler setup is only in `begin` blocks
- No impact on function calls or normal control flow

### Exception Case (Exception Raised)

- `longjmp` is fast (essentially a goto to saved context)
- Stack unwinding is implicit (just restore %esp/%ebp)
- Linear search through exception stack (acceptable for rare exceptions)

### Memory

- Each active `begin` block adds ~80 bytes to stack (exc_handler_t struct)
- Nested begin blocks stack linearly
- Typical nesting depth is small (< 5), so ~400 bytes worst case

---

## Alternatives Considered

### 1. Per-Function Exception Tables

**Approach**: Each function has a table mapping PC ranges to rescue handlers

**Pros**:
- Industry standard (C++, LLVM)
- No runtime stack overhead

**Cons**:
- Complex to implement in assembly
- Requires PC → handler lookup on every raise
- Harder to debug
- Doesn't fit simple compiler architecture

**Verdict**: Too complex for this compiler's design goals

### 2. Inline Handler Checks

**Approach**: Every function checks exception flag after each call

**Pros**:
- Simple to understand

**Cons**:
- Huge performance overhead on normal path
- Pollutes every function with exception checks
- Code bloat

**Verdict**: Unacceptable performance cost

### 3. Exception Flag + Manual Unwinding

**Approach**: Set global exception flag, each function checks and returns early

**Pros**:
- Simpler than longjmp

**Cons**:
- Requires modifying every function
- Slower unwinding (traverse each frame)
- Hard to get right with closures

**Verdict**: Inferior to longjmp approach

---

## Open Questions and Future Work

### 1. Closures and Exceptions

**Question**: What happens when exception is raised inside a closure?

**Answer**: Works automatically - exception stack is global, so `raise` in a lambda/proc/block will unwind through the exception stack regardless of where the closure was defined. The longjmp will restore the context where the handler was set up.

### 2. Threads

**Status**: Not applicable - compiler doesn't support threads

**Future**: If threads are added, exception stack must be per-thread

### 3. Backtrace Implementation Details

**Challenge**: Walking stack frames requires:
- %ebp chain walking (trivial)
- Mapping return addresses to source locations (needs debug symbols)
- Function name resolution (needs symbol table)

**Approach**: Start with stub (empty array), then enhance incrementally

### 4. Integration with GC

**Question**: Are exception handlers GC roots?

**Answer**: Exception handlers (ExceptionHandler objects) are normal heap objects, tracked by GC. The class variables `@@exc_stack` and `@@current_exception` in ExceptionRuntime are GC roots (compiler already handles class variables as roots).

### 5. Computing Label Addresses

**Question**: How does `[:addr, label]` work?

**Answer**: Similar to how Proc stores function pointers. The compiler can emit assembly to get the address of a label:
```ruby
# Compile [:addr, label]
def compile_addr(scope, label)
  @e.comment("Get address of #{label}")
  @e.movl("$#{label}", :eax)  # Load label address into %eax
  Value.new([:reg, :eax])
end
```

### 6. Why No C Code?

**Question**: Why can't we use C for this?

**Answer**: **The compiler is self-hosting**. All runtime code must be compilable by the compiler itself. Using C would:
1. Break self-hosting (C code can't be compiled by the Ruby compiler)
2. Create a maintenance nightmare (two languages to debug)
3. Violate the architectural principle of the project
4. Make the compiler dependent on external C compilation

**The pure Ruby approach is not just possible, it's REQUIRED for self-hosting.**

---

## Success Criteria

1. ✅ Basic raise/rescue works
2. ✅ Typed rescue with class matching works
3. ✅ Multiple rescue clauses work
4. ✅ Ensure blocks run in all cases
5. ✅ Bare `raise` re-raises current exception
6. ✅ Exception objects have message and class
7. ✅ Unhandled exceptions print useful error and exit
8. ✅ Selftest passes with no regressions
9. ✅ Rubyspec rescue_spec and ensure_spec pass (or mostly pass)
10. ✅ Performance: no measurable overhead on non-exception code paths

---

## Estimated Effort

- **Phase 1** (Basic raise/rescue): 8-12 hours
- **Phase 2** (Typed rescue): 8-12 hours
- **Phase 3** (Multiple rescue): 4-6 hours
- **Phase 4** (Ensure blocks): 8-12 hours
- **Phase 5** (Backtrace): 12-16 hours
- **Phase 6** (Edge cases): 8-12 hours

**Total: 48-70 hours (6-9 days)**

---

## Conclusion

The **100% self-hosted separate exception stack** approach provides:

- ✅ **Self-Hosting**: Pure Ruby implementation, compilable by the compiler itself
- ✅ **Simplicity**: Orthogonal to existing compiler architecture
- ✅ **Performance**: Zero overhead on non-exceptional paths
- ✅ **Correctness**: Based on proven Proc/stackframe mechanisms already in the compiler
- ✅ **Maintainability**: Clear separation of concerns, single language
- ✅ **Incrementality**: Can be implemented in phases with tests at each step
- ✅ **No C Dependency**: Uses existing `:stackframe` and `%s()` s-expression facilities

**Key Architectural Insight**:

Exception handling is essentially non-local control flow, just like `preturn` for Proc returns. The compiler already has all the primitives needed:
- `:stackframe` to capture %ebp
- `%s(reg esp)` to capture %esp
- Label addresses (like Proc function pointers)
- Stack restoration and jumping

By reusing these existing mechanisms, exception handling integrates naturally with zero C code.

**This is the ONLY acceptable approach** - using C would violate the self-hosting principle and is totally inexcusable.
