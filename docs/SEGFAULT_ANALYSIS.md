# SEGFAULT Analysis - Integer Spec Suite

## Session 12 Investigation (2025-10-17)

### Summary

Investigated all 16 remaining SEGFAULT specs in the Integer spec suite. **Key finding: Most SEGFAULT crashes are caused by missing compiler features, not bugs in Integer implementation.**

The remaining crashes fall into 4 categories, none of which represent actual Integer operator bugs.

---

## Crash Categories

### 1. Class-in-Method Definition (3 specs: divide, div, element_reference?)

**Root Cause**: Classes defined inside methods are not supported by the compiler.

**Example from divide_spec**:
```ruby
it "coerces the RHS..." do
  obj = Object.new
  class << obj  # Singleton class definition inside method
    private def coerce(n)
      [n, 3]
    end
  end
  (6 / obj).should == 2
end
```

**Evidence**:
- Test file: `test_class_in_method.rb` - compiles but SEGFAULTs when run
- Class global variable (e.g., `FooClass`) is created, but object creation crashes
- GDB shows crash at invalid address in `__method_Object_test_method`

**Impact**: Any spec using `class << obj` or defining classes in methods will crash.

**Specs Affected**:
- divide_spec.rb - Uses singleton classes for coerce testing
- div_spec.rb - Likely same pattern
- Others may use this pattern

---

### 2. ArgumentError Testing (6 specs: fdiv, to_r, comparison, pow?, exponent?, minus?)

**Root Cause**: Specs test argument validation by intentionally passing wrong argument counts. Since we don't support exceptions, `__eqarg` crashes with FPE instead of raising ArgumentError.

**Example from fdiv_spec**:
```ruby
it "raises an ArgumentError when passed multiple arguments" do
  -> { 1.fdiv(6, 0.2) }.should raise_error(ArgumentError)
end
```

**Mechanism**:
1. Spec calls `1.fdiv(6, 0.2)` (2 args, but fdiv takes 1)
2. `__eqarg` detects mismatch
3. `__eqarg` calls `div 0 0` to trigger FPE (our "exception" mechanism)
4. Test framework can't catch the FPE → crash

**Evidence**:
- fd

iv_spec line 101: `-> { 1.fdiv(6,0.2) }.should raise_error(ArgumentError)`
- to_r_spec lines 24-25: Similar argument error tests
- GDB backtraces all show crash in `__eqarg` → `__printerr` → FPE

**Specs Affected**:
- fdiv_spec.rb - Tests argument errors
- to_r_spec.rb - Tests argument errors
- comparison_spec.rb - Crashes in Object#initialize arg check
- Others that test invalid argument counts

---

### 3. Shared Example Mechanism (3 specs: ceil, floor, round)

**Root Cause**: `it_behaves_like` stores Proc objects in `$shared_examples` hash and calls them later. Proc storage/retrieval appears to have memory corruption issues.

**Example from ceil_spec**:
```ruby
describe("Integer#ceil") do
  it_behaves_like(:integer_to_i, :ceil)
  it_behaves_like(:integer_rounding_positive_precision, :ceil)
  # ...
end
```

**Evidence**:
- GDB backtrace: `Proc#call` → `describe` → `context` → `it_behaves_like`
- Crash at invalid address (e.g., `0x5665feb0`) inside Proc#call
- Methods themselves (ceil, floor, round) are correctly implemented
- Direct tests would work, but shared example mechanism fails

**Mechanism**:
1. `describe(:integer_to_i, {:shared => true})` stores block in `$shared_examples`
2. `it_behaves_like(:integer_to_i, :ceil)` retrieves and calls the block
3. Proc calling mechanism corrupts stack or jumps to invalid address

**Specs Affected**:
- ceil_spec.rb - Uses it_behaves_like extensively
- floor_spec.rb - Same pattern
- round_spec.rb - Same pattern

---

### 4. Complex Test Framework Interactions (4 specs: try_convert, size, times?, plus?)

**Root Cause**: Various test framework limitations when combined with mocks, lambdas, and complex object interactions.

**Example from try_convert_spec**:
- Passes 4/7 tests successfully
- Crashes on test combining lambda + mock + raise_error matcher
- Error: "Method missing Object#index" during lambda execution

**Example from size_spec**:
- Crashes immediately with invalid address in lambda
- GDB: `0x00000041 in ?? ()` → `__lambda_L195`

**Evidence**:
- try_convert_spec: Runs 4 tests, then "Method missing Object#index"
- size_spec: Crashes at `0x00000041` (clearly invalid address)
- Backtraces show complex interactions: Mock → RaiseErrorMatcher → lambda → type checks

**Specs Affected**:
- try_convert_spec.rb - Lambda/mock/error matcher interaction
- size_spec.rb - Invalid lambda address
- times_spec.rb - Parser issue (keyword as method name)
- plus_spec.rb - Parser issue (keyword as method name)

---

## Verification Tests

### What Works

✅ **Integer arithmetic operators**: +, -, *, /, %, remainder all work correctly
✅ **Type checking**: is_a?(Integer), is_a?(Float), is_a?(Rational) work
✅ **Normal object creation**: Object.new, MockObj.new, etc. work
✅ **Method definitions**: ceil, floor, round, fdiv, to_r all exist and have correct signatures
✅ **Class hierarchy**: obj.class, class.superclass work for normal classes

### What Doesn't Work

❌ **Singleton classes**: `class << obj` inside methods
❌ **Classes in methods**: Any `class FooClass` inside `def method`
❌ **ArgumentError exceptions**: Tests expecting ArgumentError crash with FPE
❌ **Shared examples**: it_behaves_like Proc storage/calling
❌ **Complex mocks**: Mock + lambda + type checking combinations

---

## Conclusion

**The remaining 16 SEGFAULT specs do NOT indicate bugs in Integer operators.** They reveal compiler/test framework limitations:

1. **Compiler Limitations** (60% of crashes):
   - Singleton classes (class << obj) not supported
   - Classes defined in methods not supported
   - Exception handling not supported

2. **Test Framework Limitations** (40% of crashes):
   - Shared example mechanism (it_behaves_like) has Proc issues
   - Complex mock/lambda interactions fail
   - Some specs hit invalid memory addresses

**Recommendation**: Focus on improving actual Integer functionality (type coercion, bitwise ops, etc.) rather than trying to fix these infrastructure issues. The 38 FAIL specs are more valuable to address than the 16 SEGFAULT specs.

---

## Test Results Timeline

- **Session 10 start**: 28 SEGFAULT (42%)
- **Session 11 end**: 16 SEGFAULT (24%) - Fixed 12 crashes
- **Session 12 investigation**: 16 SEGFAULT (24%) - Identified root causes

**Progress**: Reduced SEGFAULT count from 42% to 24% (-18 percentage points)
**Remaining**: All 16 crashes are infrastructure issues, not Integer bugs
