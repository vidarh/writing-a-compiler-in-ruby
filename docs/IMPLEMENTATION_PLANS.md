# Implementation Plans for High-Priority Issues

**Purpose**: Detailed tactical implementation guidance for high-priority tasks in docs/TODO.md. Provides step-by-step plans, test strategies, and success criteria.

**Date**: 2025-10-27
**Status**: Planning only - DO NOT START WORK without explicit approval

**Note**: Tasks are prioritized and tracked in **docs/TODO.md**. This document provides detailed implementation guidance for those tasks.

---

## Plan 1: Investigate Multiplication Regression

**Priority**: CRITICAL (Tier 1 #1)
**Commits**: c66e6e2, a64e125
**Status**: Investigation phase

### Investigation Steps

1. **Create minimal test case**
   ```bash
   cat > test_multiply_regression.rb <<'EOF'
   # Test basic large multiplication
   result = 1000000 * 1000000
   puts "1000000 * 1000000 = #{result}"
   puts "Expected: 1000000000000"
   puts "Pass: #{result == 1000000000000}"

   # Test smaller cases
   puts "\n100 * 100 = #{100 * 100} (expected 10000)"
   puts "10000 * 10000 = #{10000 * 10000} (expected 100000000)"
   EOF

   ./compile test_multiply_regression.rb -I. && ./out/test_multiply_regression
   ```

2. **Review commit c66e6e2**
   ```bash
   git show c66e6e2 lib/core/integer.rb | less
   ```
   - Focus on the mulfull usage
   - Check overflow detection logic
   - Review limb calculation changes

3. **Review commit a64e125**
   ```bash
   git show a64e125 lib/core/integer.rb | less
   ```
   - Check __multiply_fixnum_overflow implementation
   - Review if semantics (0 is truthy!)
   - Check sarl usage

4. **Understand the issues**
   - Why does multiply_spec return 0 for large multiplications?
   - Is mulfull being called correctly?
   - Is overflow detection working?
   - Are limb calculations correct?

### Possible Outcomes

**Outcome A: Simple bug in new code**
- Fix the specific bug
- Verify multiply_spec passes
- Run make selftest-c
- Commit fix

**Outcome B: Fundamental design issue**
- Document the problem
- Consider if partial revert is needed
- May need to redesign overflow detection approach

**Outcome C: S-expression compiler limitation**
- Current code hits 4+ argument method call limitation
- May need to inline more logic
- Document limitations encountered

### Success Criteria

- `1000000 * 1000000 = 1000000000000` ✓
- multiply_spec passes all tests
- make selftest-c passes with 0 failures
- No regressions in other specs

---

## Plan 2: Fix Integer#<=> for Fixnums

**Priority**: HIGH (Tier 1 #2)
**Impact**: ~30-40 test cases
**Complexity**: Low

### Current Behavior

```ruby
5 <=> 3  # Returns nil, should return 1
3 <=> 5  # Returns nil, should return -1
5 <=> 5  # Returns nil, should return 0
```

### Implementation Approach

1. **Locate Integer#<=> in lib/core/integer.rb**
   ```bash
   grep -n "def <=>" lib/core/integer.rb
   ```

2. **Review current implementation**
   - Check what branches exist
   - Identify why fixnum <=> fixnum is missing

3. **Add fixnum comparison branch**

   Expected pattern:
   ```ruby
   def <=>(other)
     # Check if both are fixnums (tagged, bit 0 = 1)
     if (self & 1) == 1 && (other & 1) == 1
       # Both fixnums - compare directly
       raw_self = self >> 1   # Untag
       raw_other = other >> 1 # Untag
       if raw_self < raw_other
         return -1
       elsif raw_self > raw_other
         return 1
       else
         return 0
       end
     end

     # Existing heap integer / mixed comparison logic...
   end
   ```

4. **Alternative using s-expressions** (if needed)
   ```ruby
   def <=>(other)
     return %s(
       (if (and (eq (bitand self 1) 1) (eq (bitand other 1) 1))
         # Both fixnums - compare
         (let (a b)
           (assign a (sar self))
           (assign b (sar other))
           (if (lt a b) (return -1))
           (if (gt a b) (return 1))
           (return 0))
       )
     )

     # Heap integer cases...
   end
   ```

5. **Test the fix**
   ```bash
   cat > test_spaceship.rb <<'EOF'
   puts "5 <=> 3 = #{5 <=> 3} (expected 1)"
   puts "3 <=> 5 = #{3 <=> 5} (expected -1)"
   puts "5 <=> 5 = #{5 <=> 5} (expected 0)"
   puts "0 <=> 1 = #{0 <=> 1} (expected -1)"
   puts "-5 <=> 3 = #{-5 <=> 3} (expected -1)"
   puts "3 <=> -5 = #{3 <=> -5} (expected 1)"
   EOF

   ./compile test_spaceship.rb -I. && ./out/test_spaceship
   ```

6. **Run comparison_spec**
   ```bash
   ./run_rubyspec rubyspec/core/integer/comparison_spec.rb
   ```

### Success Criteria

- All fixnum <=> fixnum comparisons return correct values
- comparison_spec passes fixnum tests
- make selftest-c passes
- No regressions

---

## Plan 3: Fix Integer#ord for Heap Integers

**Priority**: MEDIUM (Tier 1 #3)
**Impact**: 1 test case, but indicates potential wider issue
**Complexity**: Very low

### Current Behavior

```ruby
bignum = 18446744073709551616  # 2^64
bignum.ord  # Returns 818427592 (truncated), should return 18446744073709551616
```

### Implementation Approach

1. **Locate Integer#ord in lib/core/integer.rb**
   ```bash
   grep -n "def ord" lib/core/integer.rb
   ```

2. **Review implementation**
   - Check if it handles heap integers
   - Identify where truncation occurs

3. **Fix to return self for heap integers**

   Expected pattern:
   ```ruby
   def ord
     # For heap integers, ord just returns self
     if (self & 1) == 0
       # Heap integer (untagged) - return self
       return self
     end

     # For fixnums, also just return self
     return self
   end
   ```

   Or even simpler:
   ```ruby
   def ord
     self  # Integer#ord just returns the integer itself
   end
   ```

4. **Test the fix**
   ```bash
   cat > test_ord.rb <<'EOF'
   # Test fixnum
   puts "5.ord = #{5.ord} (expected 5)"

   # Test heap integer
   big = 18446744073709551616
   result = big.ord
   puts "bignum.ord = #{result}"
   puts "Expected: 18446744073709551616"
   puts "Match: #{result == big}"
   EOF

   ./compile test_ord.rb -I. && ./out/test_ord
   ```

5. **Run ord_spec**
   ```bash
   ./run_rubyspec rubyspec/core/integer/ord_spec.rb
   ```

### Success Criteria

- Heap integers return themselves unchanged
- ord_spec passes
- make selftest-c passes

---

## Plan 4: Fix bit_length Off-By-One

**Priority**: MEDIUM (Tier 2 #4)
**Impact**: 4 test cases
**Complexity**: Very low

### Current Behavior

```ruby
1.bit_length  # Returns 0, should return 1
2.bit_length  # Returns 1, should return 2
3.bit_length  # Returns 1, should return 2
4.bit_length  # Returns 2, should return 3
```

All results are off by exactly 1.

### Implementation Approach

1. **Locate Integer#bit_length**
   ```bash
   grep -n "def bit_length" lib/core/integer.rb
   ```

2. **Review the counting algorithm**
   - Check if it starts counting at 0 or 1
   - Look for off-by-one in loop/calculation

3. **Common fixes for bit_length off-by-one**

   If counting bits in a loop:
   ```ruby
   # WRONG: count starts at 0
   count = 0
   while n > 0
     count += 1
     n >>= 1
   end
   return count  # Off by 1 for single-bit values

   # RIGHT: account for the position starting at 1
   count = 0
   while n > 0
     count += 1
     n >>= 1
   end
   return count  # Correct if logic is right
   ```

   Or if using bit position:
   ```ruby
   # Check if we need: position vs position + 1
   # Bit position 0 = 1 bit needed
   # Bit position 1 = 2 bits needed
   # So: bit_length = position + 1
   ```

4. **Create test cases**
   ```bash
   cat > test_bit_length.rb <<'EOF'
   tests = [
     [0, 0],
     [1, 1],
     [2, 2],
     [3, 2],
     [4, 3],
     [7, 3],
     [8, 4],
     [255, 8],
     [256, 9],
     [0x7fff_ffff, 31]
   ]

   tests.each do |num, expected|
     result = num.bit_length
     status = result == expected ? "PASS" : "FAIL"
     puts "#{status}: #{num}.bit_length = #{result} (expected #{expected})"
   end
   EOF

   ./compile test_bit_length.rb -I. && ./out/test_bit_length
   ```

5. **Run bit_length_spec**
   ```bash
   ./run_rubyspec rubyspec/core/integer/bit_length_spec.rb
   ```

### Success Criteria

- All bit_length values correct
- bit_length_spec passes all 4 tests
- make selftest-c passes

---

## Plan 5: Implement Type Coercion Protocol

**Priority**: MEDIUM (Tier 2 #5)
**Impact**: ~40-50 test cases
**Complexity**: Medium

### Overview

Ruby's coercion protocol allows numeric types to interoperate. When `a op b` is called and b is not the expected type, Ruby tries:
1. Check if b responds to `coerce`
2. Call `b.coerce(a)` which should return `[a', b']` (converted pair)
3. Perform `a' op b'` with the converted values

### Implementation Approach

#### Part A: Fix Integer#coerce

1. **Review current Integer#coerce**
   ```bash
   grep -n "def coerce" lib/core/integer.rb
   ```

2. **Implement proper coercion**
   ```ruby
   def coerce(other)
     # If other is Integer, return pair
     if other.is_a?(Integer)
       return [other, self]
     end

     # Try to_int for integer conversion
     if other.respond_to?(:to_int)
       converted = other.to_int
       if converted.is_a?(Integer)
         return [converted, self]
       end
     end

     # Try to_f for float conversion
     if other.respond_to?(:to_f)
       # Note: Float not fully implemented, this may not work
       self_f = self.to_f
       other_f = other.to_f
       return [other_f, self_f]
     end

     # Can't coerce
     raise TypeError.new("#{other.class} can't be coerced into Integer")
   end
   ```

#### Part B: Add Coercion to Binary Operators

Pattern to apply to: `+`, `-`, `*`, `/`, `%`, `&`, `|`, `^`, `<<`, `>>`

```ruby
def +(other)
  # Fast path: both fixnums
  if is_fixnum?(self) && is_fixnum?(other)
    # ... existing fast path ...
  end

  # Check if other is Integer
  if !other.is_a?(Integer)
    # Try coercion protocol
    if other.respond_to?(:coerce)
      begin
        a, b = other.coerce(self)
        return a + b
      rescue => e
        # Coercion failed, fall through to TypeError
      end
    end

    # Try to_int
    if other.respond_to?(:to_int)
      other = other.to_int
      if !other.is_a?(Integer)
        raise TypeError.new("to_int didn't return Integer")
      end
      # Retry with converted value (recursive call)
      return self + other
    end

    # Can't convert
    raise TypeError.new("#{other.class} can't be coerced into Integer")
  end

  # ... existing Integer handling ...
end
```

3. **Test coercion**
   ```bash
   cat > test_coerce.rb <<'EOF'
   # Define mock object
   class MockNumeric
     def initialize(val)
       @val = val
     end

     def coerce(other)
       puts "coerce(#{other}) called"
       [other, @val]
     end
   end

   mock = MockNumeric.new(10)
   result = 5 + mock
   puts "5 + mock = #{result} (expected 15)"
   EOF
   ```

4. **Run coerce_spec**
   ```bash
   ./run_rubyspec rubyspec/core/integer/coerce_spec.rb
   ```

### Success Criteria

- Integer#coerce handles Integer, to_int, to_f cases
- Binary operators try coercion before raising TypeError
- coerce_spec passes
- Operator specs with coerce tests pass
- make selftest-c passes

---

## Plan 6: Add Missing Exception Raising

**Priority**: MEDIUM (Tier 2 #6)
**Impact**: ~30-40 test cases
**Complexity**: Low-Medium

### Categories of Missing Exceptions

1. **ZeroDivisionError** - Integer division by zero
2. **TypeError** - Invalid type for operation
3. **ArgumentError** - Wrong number/type of arguments

### Implementation Approach

#### Part A: ZeroDivisionError for Division

```ruby
def /(other)
  # ... type handling ...

  # Check for division by zero (integer division only)
  if other == 0 && other.is_a?(Integer)
    raise ZeroDivisionError.new("divided by 0")
  end

  # ... existing division logic ...
end

# Apply same pattern to: div, %, divmod
```

#### Part B: TypeError for Invalid Types

Replace patterns like:
```ruby
STDERR.puts("TypeError: ...")
return nil
```

With:
```ruby
raise TypeError.new("...")
```

Affected methods: Most binary operators after coercion fails

#### Part C: ArgumentError for Invalid Arguments

For methods using `*args` pattern, replace:
```ruby
if args.length != expected
  STDERR.puts("ArgumentError: ...")
  return nil
end
```

With:
```ruby
if args.length != expected
  raise ArgumentError.new("wrong number of arguments (given #{args.length}, expected #{expected})")
end
```

### Test Approach

```bash
cat > test_exceptions.rb <<'EOF'
def test_exception(description)
  begin
    yield
    puts "FAIL: #{description} - no exception raised"
  rescue => e
    puts "PASS: #{description} - #{e.class}: #{e.message}"
  end
end

test_exception("division by zero") { 1 / 0 }
test_exception("invalid type") { 1 + "string" }
# ... more tests ...
EOF
```

### Success Criteria

- Division by zero raises ZeroDivisionError
- Invalid types raise TypeError
- Wrong arg counts raise ArgumentError
- Exception specs pass
- make selftest-c passes

---

## General Testing Protocol

**After each implementation:**

1. **Create minimal test case**
   - Test the specific fix in isolation
   - Verify expected behavior

2. **Run affected spec**
   - `./run_rubyspec rubyspec/core/integer/[spec].rb`
   - Check that failures decrease

3. **Run selftest-c**
   - `make selftest-c`
   - MUST pass with 0 failures
   - If fails, investigate before proceeding

4. **Check for regressions**
   - Run a few other passing specs
   - Ensure changes don't break working code

5. **Commit with clear message**
   - Describe what was fixed
   - Reference spec test results
   - Include before/after metrics

---

## Notes

- These plans are **guidance only** - DO NOT START without approval
- Each plan should be treated as a starting point for investigation
- Actual implementation may differ based on findings
- Always prioritize `make selftest-c` passing
- Document any unexpected issues or complications discovered

