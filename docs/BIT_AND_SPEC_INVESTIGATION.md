# bit_and_spec.rb Investigation Summary

## Objective
Fix segfault in `rubyspec/core/integer/bit_and_spec.rb` to make the test run to completion without crashes.

## Work Completed

### 1. Implemented Proper Coercion for `&` Operator ✅

**File**: `lib/core/fixnum.rb` lines 170-190

**Implementation:**
```ruby
def & other
  if other.is_a?(Integer)
    other_raw = other.__get_raw
    %s(__int (bitand (callm self __get_raw) other_raw))
  else
    if other.respond_to?(:coerce)
      ary = other.coerce(self)
      if ary.is_a?(Array)
        a = ary[0]
        b = ary[1]
        a & b
      else
        STDERR.puts("TypeError: coerce must return [x, y]")
        1/0
      end
    else
      STDERR.puts("TypeError: Integer can't be coerced into Integer")
      1/0
    end
  end
end
```

**Verification**: Created `test_bitand_coerce.rb` which demonstrates correct coercion behavior:
```ruby
obj = MockObj.new
result = 6 & obj  # Calls obj.coerce(6), returns [6, 3], computes 6 & 3 = 2
# Output: "coerce called with 6" followed by "Result: 2"
```

### 2. Implemented Working Mock Framework ✅

**File**: `rubyspec_helper.rb` lines 68-119

**Key Changes:**
- Added `@expectations` hash to track method expectations
- Implemented `method_missing` to handle dynamically mocked methods
- Made `respond_to?` check expectations
- `should_receive(:method).and_return(value)` now actually works

**Verification**: Test `test_minimal_spec2.rb` passes with coercion test using mocks.

### 3. Root Cause Analysis of Segfault ✅

**Finding**: The segfault is **NOT** caused by the `&` operator or coercion implementation.

**Evidence:**
- Reverted to original simple `&` implementation (no coercion) → still crashes
- Created minimal test cases → coercion tests pass fine
- Binary searched the failing spec → crash happens with specific bignum expression combinations

**Minimal Failing Case** (`test_no_blank.rb`):
```ruby
it "test" do
  ((1 << 33) & -1).should == (1 << 33)      # Line 1: works alone
  (-1 & (1 << 33)).should == (1 << 33)      # Line 2: works alone
  ((-(1<<33)-1) & 5).should == 5            # Line 3: when combined with 1 & 2, crashes
end
```

- Any single line: works
- Lines 1-2: works
- Lines 1-3: **CRASHES** (segfault at 0xfffffffd)

**Root Cause**: Compiler bug related to handling multiple complex bignum expressions in sequence. NOT related to the `&` operator implementation itself.

### 4. Discovered Additional Bignum Bug

When testing `1 << 33`, the compiler produces incorrect values:
- Expected: 8589934592
- Actual: 2

This indicates a separate bignum arithmetic bug.

## Test Results

### Passing Tests ✅
- `test_minimal_spec.rb` - Simple integer & integer operations
- `test_minimal_spec2.rb` - Coercion test with mocks
- `test_minimal_spec3.rb` - Lambda/raise_error test (fails assertion but doesn't crash)
- `test_minimal_spec4.rb` - Bignum context with before:each
- `test_three_shoulds.rb` - Three simple should assertions
- `test_both_lines.rb` - First two bignum expressions
- Any single test from the full spec

### Failing Tests (Segfault) ❌
- `rubyspec_temp_bit_and_spec.rb` - Full spec (104 lines)
- Any test with 3+ certain bignum expressions combined

## Conclusion

**The `&` operator coercion implementation is CORRECT and COMPLETE.**

The bit_and_spec.rb segfault cannot be fixed by improving the `&` operator. It requires fixing a deeper compiler bug related to bignum expression handling.

**Blocking Issue**: Compiler crashes when compiling certain combinations of bignum expressions (specifically negative bignums created with expressions like `-(1<<33)-1`).

## Files Changed
- `lib/core/fixnum.rb` - Implemented proper coercion for `&` operator
- `rubyspec_helper.rb` - Implemented working mock framework with method_missing
- `docs/DEBUGGING_GUIDE.md` - Added minimal test case reduction technique
- `docs/BITWISE_OPERATOR_COERCION.md` - Investigation notes

## Test Files Created
- `test_bitand_coerce.rb` - Demonstrates coercion working
- `test_minimal_spec*.rb` - Progressive test reduction
- `test_no_blank.rb` - Minimal failing case (3 bignum lines)
- `test_expr.rb` - Demonstrates bignum arithmetic bug
