# Compile-Time Execution and State Serialization

## The Reality

Ruby's dynamic nature means:

```ruby
class Integer
  x = compute_something()  # Code INSIDE class definition

  define_method(:foo) { x }  # Dynamic method definition

  def bar; x; end  # References x from class scope
end

result1 = Integer.new.foo  # Call foo

class Integer  # Reopen
  def foo; 42; end  # Redefine foo
end

result2 = Integer.new.foo  # Must call NEW foo

$global = Integer  # Store class in global
```

**Implications:**

1. **Code occurs everywhere** - inside classes, between classes, in methods
2. **Methods are redefinable** - Integer.foo can change between calls
3. **Everything is stateful** - if it exists at compile time and could be referenced later, it must exist at runtime
4. **Objects persist** - anything stored in a global/constant must survive

**Therefore:** We cannot cherry-pick what to execute. We must execute *everything* up to the boundary.

## What We're Actually Doing

Not "partial evaluation" - we're doing **checkpoint and restore**:

1. **Execute** the entire program at compile time (in an interpreter)
2. When we hit the boundary (marker or side effect), **freeze** the entire state
3. **Serialize** that frozen state into the binary
4. At runtime, **restore** from the serialized state
5. Continue execution from where we left off

This is like Smalltalk images or process snapshots.

## The Process

### Step 1: Execute Until Boundary

```ruby
# Everything below executes in compile-time interpreter

class Integer
  MAGIC = File.read("config.txt").to_i  # Execute File.read at compile time

  def foo; MAGIC; end
end

x = Integer.new  # Create object at compile time
$global = x      # Store in global

class Integer
  def foo; 99; end  # Redefine foo
end

y = Integer.new.foo  # Execute foo (NEW version) at compile time
RESULT = y + 10      # RESULT = 109

__compiler_end_evaluation  # <-- FREEZE HERE

# Everything below compiles normally
puts $global.foo  # Must work - $global must exist at runtime
puts RESULT       # Must work - RESULT must exist
```

### Step 2: Capture State

At the freeze point, we have:

**Classes:**
- Integer class object with vtable containing redefined `foo`

**Objects:**
- `x` = Integer instance created at line 8
- Anonymous Integer instance created at line 18 (may be GC'd)

**Globals:**
- `$global` = reference to `x`

**Constants:**
- `Integer::MAGIC` = contents of config.txt as integer
- `RESULT` = 109

**This is the complete state** - everything that exists must be serialized.

### Step 3: Serialize State

Generate assembly that reconstructs this exact state:

```asm
.data

# Integer class with final vtable
__class_Integer:
    .long __vtable_Integer
    .long __class_Object      # superclass
    # ... other class fields

__vtable_Integer:
    .long __method_Integer_foo_v2  # The REDEFINED version
    # ... other methods

# The object 'x'
__compiled_obj_1:
    .long __class_Integer
    # ... object fields

# Global variables
__global_$global:
    .long __compiled_obj_1    # Points to 'x'

# Constants
__const_Integer_MAGIC:
    .long 42  # (or whatever was in config.txt)

__const_RESULT:
    .long 109

.text

# The redefined Integer#foo
__method_Integer_foo_v2:
    movl $99, %eax
    ret

main:
    # State already exists!
    # Runtime code starts here:

    # puts $global.foo
    movl __global_$global, %eax
    # ... call foo ...
```

### Step 4: Runtime Continues

The runtime code sees:
- Integer class exists with correct vtable
- `$global` exists and points to a real Integer object
- `RESULT` exists and equals 109
- Everything works as if initialization had run

## The Hard Parts

### Problem 1: Object Graph Serialization

Objects can reference each other arbitrarily:

```ruby
class Node
  attr_accessor :value, :next
end

a = Node.new
b = Node.new
a.next = b
b.next = a  # Cycle!

$head = a
```

**Solution:** Serialize entire object graph with cycle detection:

```asm
__obj_1:  # Node 'a'
    .long __class_Node
    .long __obj_1_ivars

__obj_1_ivars:
    .long __sym_value, 0       # @value = nil
    .long __sym_next, __obj_2  # @next = b

__obj_2:  # Node 'b'
    .long __class_Node
    .long __obj_2_ivars

__obj_2_ivars:
    .long __sym_value, 0       # @value = nil
    .long __sym_next, __obj_1  # @next = a (cycle!)
```

**Challenge:** Need to serialize:
- All object types (Integer, String, Array, Hash, custom classes)
- Instance variables
- References between objects
- Special cases (symbols, frozen strings, etc.)

### Problem 2: Method Redefinition Tracking

```ruby
class Integer
  def foo; 1; end
end

Integer.new.foo  # foo version 1

class Integer
  def foo; 2; end  # Redefine
end

Integer.new.foo  # foo version 2
```

The vtable must reflect the FINAL state after all redefinitions.

**Solution:** Track vtable changes throughout execution:

```ruby
class CompileTimeExecutor
  def execute_method_definition(klass, name, body)
    # Check if method already exists
    if @vtables[klass][name]
      # Redefining - old version no longer matters (unless captured in closure)
      @vtables[klass][name] = compile_new_version(body)
    else
      # New method
      @vtables[klass][name] = compile_new_version(body)
    end
  end
end
```

**Complication:** Old method versions might be captured in closures:

```ruby
class Integer
  def foo; 1; end
end

old_foo = Integer.new.method(:foo)  # Capture old version

class Integer
  def foo; 2; end
end

Integer.new.foo      # => 2 (new version)
old_foo.call         # => 1 (old version!)
```

Both versions must exist in the binary!

### Problem 3: Closures

```ruby
def make_counter
  x = 0
  lambda { x += 1 }
end

$counter = make_counter

__compiler_end_evaluation

puts $counter.call  # Must work - closure must exist at runtime
```

**Problem:** The closure captures `x`. At runtime, `$counter` must be a real Proc that still closes over `x`.

**Solution:** Serialize closure state:

```asm
__closure_env_1:
    .long 0  # x = 0

__closure_1:
    .long __class_Proc
    .long __closure_1_code
    .long __closure_env_1

# ... and the closure code must work with this environment
```

**This is very complex.**

### Problem 4: Classes as First-Class Objects

```ruby
$classes = [Integer, String, Array]

__compiler_end_evaluation

$classes.each { |klass| puts klass.new }
```

The array must contain actual references to the class objects.

```asm
__array_1_data:
    .long __class_Integer
    .long __class_String
    .long __class_Array

__array_1:
    .long __class_Array
    .long 3  # size
    .long __array_1_data

__global_$classes:
    .long __array_1
```

## A Simpler Starting Point

Given the complexity, start with something achievable:

### Phase 0: Just Classes and Simple Constants

**Restriction:** Only allow:
- Class definitions (no code inside except method definitions)
- Method definitions (code can be arbitrary, but executed when called, not at definition time)
- Simple constant assignments (literals only)

```ruby
class Integer
  def foo; 1; end  # OK - method body not executed at definition time
  def bar; 2; end
end

CONST = 42  # OK - literal

__compiler_end_evaluation
```

**NOT allowed:**
```ruby
class Integer
  x = compute()  # NOT allowed - code at class scope
  def foo; x; end
end

CONST = File.read("x")  # NOT allowed - computation
```

**Implementation:**
1. Parse class definitions
2. Compile all methods (as usual)
3. Build final vtables
4. Emit vtables as static data
5. Emit simple constants as static data

**Benefit:** Eliminates the 541+ initialization calls.

**Limitation:** Doesn't help with computed constants, object initialization, etc.

**Required refactoring:** lib/core/ must be restructured to avoid code at class scope.

### Phase 1: Add Code Execution (The Full Problem)

Allow arbitrary code before the marker.

**Requirements:**
1. Full Ruby interpreter (or use MRI via eval)
2. Object serialization system
3. Closure serialization
4. GC root tracking (what objects must survive)

**This is essentially building a Ruby image system.**

**Estimated effort:** 6-12 months of full-time work.

## Using MRI as the Interpreter

We could use MRI itself to execute the compile-time code:

```ruby
class CompileTimeExecutor
  def execute(ast, boundary)
    # Convert AST back to Ruby source
    source = ast_to_source(ast[0...boundary])

    # Execute in isolated binding
    binding = create_clean_binding
    eval(source, binding)

    # Capture state from binding
    classes = binding.eval("ObjectSpace.each_object(Class).to_a")
    globals = binding.eval("global_variables.map { |g| [g, eval(g.to_s)] }.to_h")
    # ... etc

    # Serialize
    serialize_state(classes, globals, ...)
  end
end
```

**Pros:**
- Don't need to build Ruby interpreter
- Handles all Ruby semantics correctly
- Can use ObjectSpace to inspect state

**Cons:**
- Circular dependency (need Ruby to compile Ruby)
- Hard to serialize arbitrary MRI objects
- Sandboxing is complex

## Recommendation

**Option 1: Phase 0 Only**
- Restrict code to class definitions and literals
- Refactor lib/core/ to comply
- Emit static vtables
- **Effort:** 4-6 weeks
- **Benefit:** Fast startup (no initialization calls)
- **Limitation:** No computed constants, no object serialization

**Option 2: Full System**
- Use MRI for compile-time execution
- Build object serialization system
- Handle closures, cycles, etc.
- **Effort:** 6-12 months
- **Benefit:** Full power (file embedding, computed constants, object graphs)
- **Limitation:** Very complex, high risk

**Option 3: Defer**
- Current system works
- Initialization overhead is ~50ms (not critical for many use cases)
- Focus effort elsewhere (e.g., finishing bignum support, adding missing features)

## My Actual Recommendation

**Do Option 3: Defer this entirely.**

**Why:**
1. This is fundamentally hard - it's a Ruby image system
2. The benefit (50ms startup improvement) is nice but not critical
3. The effort (6-12 months for full system) is very high
4. The risk is high (serialization bugs, determinism issues, closure problems)
5. There are simpler wins available (inlining, better codegen, etc.)

**If you really want to pursue this:**

Start with **Option 1: Phase 0** to get a feel for the complexity. If lib/core/ can't be easily refactored to comply, that's a sign that the full system (Option 2) is needed, which is probably not worth it.

## Inlining (Separate, Simpler)

Inlining is much simpler and doesn't require state serialization:

**Idea:** For frozen classes, inline small methods at call sites.

**Implementation:**
1. Defer assembly emission - use s-expressions as IR
2. After all classes are defined (even without execution), mark them frozen
3. During code generation, for small methods on frozen classes, inline the method body instead of emitting vtable dispatch

**Example:**
```ruby
class Integer
  def even?; (self & 1) == 0; end
end
Integer.freeze

# Later:
x.even?

# Normally compiles to:
#   call *vtable_offset_even(%eax)

# With inlining:
#   andl $1, %eax
#   cmpl $0, %eax
```

**Benefit:** Eliminate dispatch overhead for tiny methods.

**Effort:** 4-8 weeks (need IR phase, inlining heuristics).

**This is achievable and valuable without the serialization complexity.**

## Conclusion

**Compile-time execution with state serialization is essentially building a Ruby image system** - similar to Smalltalk images or SBCL's save-lisp-and-die.

**This is hard:**
- Full Ruby interpreter needed
- Object graph serialization (with cycles, closures, classes-as-objects)
- Method redefinition tracking
- GC root tracking

**Time estimate:** 6-12 months for full system.

**Recommendation:** Don't do this. Focus on simpler wins like inlining instead.

**If you insist:** Start with Phase 0 (classes + literals only) to validate the approach, but expect to need the full system.
