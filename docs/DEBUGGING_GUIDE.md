# Debugging Guide for Ruby Compiler

This guide documents effective debugging patterns discovered while working on this Ruby compiler. These techniques have proven successful for diagnosing and fixing compilation issues, runtime crashes, and language feature gaps.

## Table of Contents

1. [Quick Reference](#quick-reference)
2. [Debugging Compilation Failures](#debugging-compilation-failures)
3. [Debugging Segfaults and Runtime Crashes](#debugging-segfaults-and-runtime-crashes)
4. [Debugging Parser Issues](#debugging-parser-issues)
5. [Debugging Operator and Method Issues](#debugging-operator-and-method-issues)
6. [Testing and Verification](#testing-and-verification)
7. [Common Patterns and Solutions](#common-patterns-and-solutions)

## Quick Reference

### Most Common Issues and Their Fixes

| Symptom | Likely Cause | First Steps |
|---------|-------------|-------------|
| "Method missing X#method" | Method not in vtable | Check if method exists in class, add if missing |
| FPE (Floating Point Exception) | Argument count mismatch | Check `__eqarg` calls with GDB, verify method signature |
| SIGSEGV at address 0x1 or similar | Calling through nil/fixnum | Check vtable entry exists, method properly defined |
| "Unable to resolve X statically" | Missing class/constant | Check if class is defined, may need stub |
| Parse error | Parser doesn't support syntax | Check parser.rb, may need new operator/keyword support |

## Debugging Compilation Failures

### Pattern: Parse Tree Analysis

When compilation fails, examine the parse tree to understand how the compiler interprets your code.

```bash
# View the full parse tree
ruby -I. ./driver.rb test_file.rb --parsetree

# Search for specific patterns
ruby -I. ./driver.rb test_file.rb --parsetree 2>&1 | grep "pattern"
```

**Example:** When investigating unary `+`:
```bash
ruby -I. ./driver.rb test_simple_uplus.rb --parsetree 2>&1 | grep -A10 "assign y"
# Found: (assign y (callm ((sexp 11)) +@ ()))
# Issue: Double-wrapped receiver ((sexp 11)) instead of (sexp 11)
```

### Pattern: Incremental Simplification

When a complex file fails to compile:

1. Create a minimal reproduction case
2. Add complexity incrementally until it breaks
3. Identify the exact construct causing failure

**Example:** Rational literal investigation:
```ruby
# Start simple
puts 5r  # Works?

# Add complexity
x = 6/5r  # Works?
puts x

# Use in expression
result = 3.ceildiv(6/5r)  # Where does it fail?
```

### Pattern: Missing Feature Detection

Compilation failures often reveal missing language features. Check:

1. **Parser support**: Is the syntax recognized? (`parser.rb`, `tokens.rb`)
2. **Transformation**: Does it transform correctly? (`transform.rb`)
3. **Compilation**: Does it generate assembly? (`compiler.rb`, `compile_*.rb`)
4. **Runtime**: Does the method exist? (`lib/core/*.rb`)

## Debugging Segfaults and Runtime Crashes

### Pattern: GDB Backtrace Analysis

Always start with a backtrace to identify the crash location:

```bash
gdb ./out/test_program <<'EOF'
run < /dev/null
bt 20
quit
EOF
```

**What to look for:**
- Method names in stack: Identifies which method failed
- `__printerr`: Indicates error handler was called (check for `div 1 0`)
- `__eqarg`: Argument count mismatch
- Address like `0x1`, `0xb`: Attempting to call a fixnum value as function

### Pattern: Crash Address Analysis

When crashing at specific addresses:

```bash
# Check what the crash address represents
gdb ./out/test_program <<'EOF'
run < /dev/null
info registers
x/10i $eip-20  # Disassemble around crash
quit
EOF
```

**Address meanings:**
- `0x00000001`: Fixnum 0 (value `(0 << 1) | 1`)
- `0x0000000b`: Fixnum 5 (value `(5 << 1) | 1`)
- Odd addresses: Tagged fixnums
- Even addresses: Likely pointers (objects, strings, etc.)

### Pattern: Method Resolution Debugging

For "Method missing" errors:

1. **Verify the class**:
```bash
# Check which class is being used
gdb ./out/test <<'EOF'
break __method_missing
run < /dev/null
frame 1
# Examine the object's class
quit
EOF
```

2. **Check vtable**:
```bash
# Search for method in vtable
grep "__method_ClassName_methodname" out/program.s
grep "__voff__methodname" out/program.s
```

3. **Verify method definition**:
```bash
# Check if method is defined in class
grep "def methodname" lib/core/classname.rb
```

### Pattern: Uninitialized Global Detection

If accessing an uninitialized global causes crashes:

**Symptom:** Calling `.method` on nil causes "Method missing NilClass#method"

**Solution:**
1. Check initialization order in files
2. Move global initializations before methods that use them
3. Verify globals are initialized at file top-level, not in method definitions

**Example Fix:**
```ruby
# WRONG: Used before defined
def it(&block)
  $before_each_blocks.each { |b| b.call }  # Crashes if nil!
end

$before_each_blocks = []  # Too late!

# RIGHT: Define before use
$before_each_blocks = []

def it(&block)
  $before_each_blocks.each { |b| b.call }  # Now safe
end
```

### Pattern: Type Tag Investigation

For bitwise/arithmetic operations that crash:

**Check if result is properly tagged:**
```ruby
# Wrong: Returns untagged integer
def & other
  %s(bitand (callm self __get_raw) (callm other __get_raw))
end

# Right: Wrap result to restore tag
def & other
  %s(__int (bitand (callm self __get_raw) (callm other __get_raw)))
end
```

**Why:** Bitwise operations strip the type tag. Must re-apply with `__int()`.

## Debugging Parser Issues

### Pattern: Token-by-Token Analysis

When parser fails on specific syntax:

1. **Check tokenizer output**:
```ruby
# Add debug output in tokens.rb
def self.expect(s)
  puts "Parsing: #{s.peek(10)}"  # See what's being parsed
  # ... rest of method
end
```

2. **Verify operator precedence**:
```bash
grep "your_operator" operators.rb
```

3. **Check if operator needs special handling**:
```bash
grep "your_operator" shunting.rb
```

### Pattern: Symbol Parsing

For operator symbols (`:+`, `:-@`, etc.):

**Check:** Does `sym.rb` recognize the symbol?

```ruby
# sym.rb pattern
elsif s.peek == ?-
  s.get
  if s.peek == ?@     # Check for unary operator
    s.get
    return :":-@"
  end
  return :":-"
```

**Verification:**
```ruby
# Test that symbols parse correctly
require_relative 'sym'
# Symbol :-@ should be recognized as single token
```

### Pattern: Operator Transformation

For unary operators, check transformation in `transform.rb`:

```ruby
# transform.rb - rewrite_operators method
if e[0] == :+ && e.length == 2    # Unary plus
  e[3] = E[]         # args = []
  e[2] = :+@         # method = :+@
  e[1] = e[1]        # object = operand (DON'T wrap with E[])
  e[0] = :callm      # op = :callm
end
```

**Common mistake:** Using `E[e[1]]` double-wraps the argument.

## Debugging Operator and Method Issues

### Pattern: Missing Operator Implementation

Symptoms:
- "FIXME: Dummy" in error output
- Wrong results from operations
- Operations don't work at all

**Check locations:**
1. `compile_arithmetic.rb` - Compilation methods (`compile_add`, `compile_sall`, etc.)
2. `emitter.rb` - Assembly instruction emitters (`addl`, `sall`, etc.)
3. `lib/core/fixnum.rb` - Method definitions (`def +`, `def <<`, etc.)

**Example fix for shift operators:**

```ruby
# 1. Add emitter (emitter.rb)
def sall src, dest; emit(:sall, src, dest); end

# 2. Implement compiler (compile_arithmetic.rb)
def compile_sall(scope, left, right)
  # Evaluate shift amount -> %ecx
  compile_eval_arg(scope, left)
  @e.movl(@e.result, :ecx)
  # Evaluate value to shift
  compile_eval_arg(scope, right)
  # Perform shift
  @e.sall(:cl, @e.result)
  Value.new([:subexpr])
end

# 3. Define method (lib/core/fixnum.rb)
def << other
  %s(__int (sall (sar other) (sar self)))
end
```

### Pattern: Type Coercion

When methods need to handle non-Integer arguments:

```ruby
def ceildiv(other)
  # Convert to integer if it responds to to_int
  if other.respond_to?(:to_int)
    other = other.to_int
  end
  # Now use as integer
  # ...
end
```

**Where to put coercion:**
- In the method (e.g., `ceildiv`) - CORRECT for application-level
- Not in `__get_raw` - That's too low-level
- Operators should implement proper coercion protocol

## Testing and Verification

### Pattern: Test-Driven Fix Cycle

1. **Create minimal test**:
```ruby
# test_feature.rb
puts "Testing..."
result = 5 << 2  # Or whatever you're testing
puts result      # Should print 20
puts "Done!"
```

2. **Compile and run**:
```bash
./compile test_feature.rb && ./out/test_feature
```

3. **Debug if crashes**:
```bash
gdb ./out/test_feature <<'EOF'
run < /dev/null
bt
quit
EOF
```

4. **Check assembly if wrong result**:
```bash
grep -A20 "test pattern" out/test_feature.s
```

5. **Verify selftest still passes**:
```bash
make selftest
```

### Pattern: Spec Testing

For RubySpec tests:

```bash
# Run single spec
./run_rubyspec rubyspec/core/integer/method_spec.rb

# Count failures
./run_rubyspec rubyspec/ --count-failures

# Debug specific failure
./run_rubyspec rubyspec/core/integer/method_spec.rb
gdb ./out/rubyspec_temp_method_spec
```

### Pattern: Regression Prevention

After fixing a bug:

1. **Verify the fix**:
   - Test the specific failing case
   - Test edge cases
   - Test with different types

2. **Verify no regressions**:
```bash
# Always run selftest
make selftest

# Run related specs
./run_rubyspec rubyspec/core/integer/*.rb
```

3. **Document the fix**:
   - Update TODO.md with what was fixed
   - Add comments explaining why the fix works
   - Reference issue in commit message

## Common Patterns and Solutions

### Pattern: Unimplemented Feature Detection

**Symptom:** Parser error or "FIXME" in output

**Investigation:**
1. Search codebase for "FIXME" near the error
2. Check if similar features are implemented
3. Look for stubs or placeholder code

**Example:**
```bash
# Find FIXME comments
grep -r "FIXME.*shift" .

# Found: compile_sall and compile_sarl are dummy implementations
# Solution: Implement them properly
```

### Pattern: Argument Order Issues

**Symptom:** Operations produce wrong results but don't crash

**Check:** S-expression argument order in `%s(...)` expressions

**Example:**
```ruby
# WRONG order for left shift
def << other
  %s(__int (sall (sar self) (sar other)))
end
# Result: shifts 'other' by 'self' amount

# RIGHT order
def << other
  %s(__int (sall (sar other) (sar self)))
end
# Result: shifts 'self' by 'other' amount
```

**Verification:** Check the `compile_*` method to see argument order.

### Pattern: Missing Method in Vtable

**Symptom:** "Method missing ClassName#methodname"

**But:** Method IS defined in the class file

**Cause:** Method not added to vtable during compilation

**Solution:**
1. Ensure method is defined in class file loaded by compiler
2. Check that class file is properly required
3. Verify method name matches exactly (including special chars like `+@`)

### Pattern: Assembly Generation Bugs

**Symptom:** Compiler generates invalid assembly

**Debug:**
```bash
# Try to assemble the output
gcc -m32 -c out/test.s 2>&1 | head -20

# Look for error line
grep "Error" output
```

**Common issues:**
- Missing emitter method (e.g., `andl`, `orl`)
- Invalid instruction (check x86 documentation)
- Wrong operand order (x86 is `instruction source, dest`)

### Pattern: Bootstrap Issues

**Symptom:** Compiler can't compile itself or certain constructs

**Constraints:**
- Can't use exceptions (begin/rescue) in compiler source
- Can't use regexps
- Can't use eval
- Limited metaprogramming

**Solutions:**
- Use simple Ruby constructs only
- Avoid features not yet implemented
- Mark with `@bug` comment if working around compiler limitation
- Test with MRI first, then with compiled compiler

## Quick Debugging Checklist

When encountering an issue, check these in order:

- [ ] Does it compile with MRI Ruby? (Rules out syntax errors)
- [ ] Does selftest pass? (Ensures compiler itself works)
- [ ] Is the feature implemented? (Check for FIXMEs)
- [ ] Is the method in the vtable? (Search assembly output)
- [ ] Are types properly tagged? (Check for `__int` wrapping)
- [ ] Is argument order correct? (Check s-expression vs implementation)
- [ ] Are globals initialized before use? (Check file order)
- [ ] Is the transformation correct? (Use `--parsetree`)

## Resources

- **Parser debugging**: Use `--parsetree` flag with driver.rb
- **Assembly inspection**: Generated `.s` files in `out/` directory
- **GDB debugging**: Use `gdb ./out/program` for runtime issues
- **Selftest verification**: Always run `make selftest` after changes

## See Also

- `ARCHITECTURE.md` - Overall compiler architecture
- `TODO.md` - Known issues and planned improvements
- `segfault_analysis_2025-10-09.md` - Detailed analysis of spec failures
- `bitwise_operator_coercion_bug.md` - Specific bug investigation example
