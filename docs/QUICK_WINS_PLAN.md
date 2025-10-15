# RubySpec Quick Wins Plan - 2025-10-14

## Current Baseline

**Test Coverage** (from enhanced run_rubyspec):
- **Total test cases**: 747 individual tests across 67 spec files
- **Passing**: 142 test cases (19%)
- **Failing**: 605 test cases (81%)

**File-Level Summary**:
- **PASS**: 11 files (16%)
- **FAIL**: 22 files (33%)
- **SEGFAULT**: 33 files (49%)
- **COMPILE FAIL**: 1 file (2%) - digits_spec.rb (stabby lambda causes infinite loop)

## Root Causes (Ranked by Impact)

### 1️⃣ Bignum Implementation Issues - HIGHEST IMPACT
**Affects**: 200+ test cases across 40+ spec files

**Problem**:
- `bignum_value()` helper returns fake values (100000+n) instead of real 64-bit bignums
- Multi-limb heap integers have comparison bugs
- to_s for large values returns wrong results

**Examples**:
```
abs_spec.rb:     Expected 184467440 but got 100039
to_s_spec.rb:    Expected "18446744073709551625" but got "100009"
even_spec.rb:    Expected true but got false (bignum even? test)
```

**Fix Impact**: +100-120 test cases → 35-40% pass rate

### 2️⃣ Type Coercion Issues - HIGH IMPACT
**Affects**: 100+ test cases across 25+ spec files

**Problem**:
- Operators call `__get_raw` without type checking
- "Method missing Symbol#__get_raw" crashes
- No to_int coercion before arithmetic

**Examples**:
```
plus_spec.rb:      Method missing Symbol#__get_raw → FPE
multiply_spec.rb:  Method missing NilClass#__multiply_heap_by_fixnum → FPE
bit_and_spec.rb:   TypeError: Integer can't be coerced
```

**Fix Impact**: +50-60 test cases → 45-50% pass rate

### 3️⃣ Method Implementation Gaps - MEDIUM IMPACT
**Affects**: 50+ test cases across 15+ spec files

**Problem**:
- divmod: Immediate FPE crash
- Heap integer methods returning nil instead of objects
- Negative shift handling broken

**Fix Impact**: +30-50 test cases → 50-55% pass rate

## Quick Win Strategy

### Phase 1: Bignum Foundation (Week 1)

#### Step 1.0: PREREQUISITE - Large Integer Literal Support (4-8 hours) ⚠️ CRITICAL

**Problem**: Cannot implement bignum_value() properly because tokenizer truncates integer literals.

**Current Behavior** (tokens.rb:152-194):
```ruby
# 29-bit limit (accounting for 1-bit tagging)
# Stop parsing if number gets too big to prevent overflow
max_safe = 134217728  # 2^27 - Stop before we overflow

# ...
break if num > max_safe  # Line 193: Truncates large literals
```

**Required Changes**:

**1. Update tokens.rb Number.expect** (3-4 hours):
```ruby
# Parse full integer value without truncation
# After parsing, check if value fits in tagged fixnum:
# - If num <= 2^29-1: Return [:int, num] (tagged fixnum)
# - If num > 2^29-1: Return [:bignum_literal, num_string] (to be converted to heap integer)
```

**2. Update parser.rb** (1-2 hours):
- Handle [:bignum_literal, string] token
- Generate AST for heap integer allocation:
  ```ruby
  # Pseudo-AST:
  [:bignum_alloc, string_value]
  ```

**3. Update sexp.rb SEXParser#parse_exp** (1 hour) - **ENFORCE FIXNUM-ONLY**:
```ruby
def parse_exp
  ws
  ret = expect(Atom, Quoted, Methodname) || parse_int_safe_only || parse_sexp
  ws
  return ret
end

def parse_int_safe_only
  # S-expressions CANNOT use heap integers - only tagged fixnums
  # This is a hard constraint, not a warning
  val = expect(Int) or return nil

  # ENFORCE: Integer must fit in tagged fixnum (30-bit signed)
  # Valid range: -536870912 to 536870911 (-2^29 to 2^29-1)
  if val.abs > 536870911  # 2^29 - 1
    raise "FATAL: Integer literal in s-expression exceeds tagged fixnum range: #{val}\n" +
          "S-expressions require immediate values only (max ±2^29-1).\n" +
          "Use computed values instead of large literals in s-expressions."
  end
  val
end
```

**Why This Is Critical**:
- S-expressions compile to low-level assembly operations
- Assembly expects immediate integer values (tagged fixnums)
- Heap integers are pointers, not immediate values
- Using heap integers in s-expressions = memory corruption/crashes
- This is **NOT** a feature limitation - it's a fundamental architectural constraint

**4. Update compiler.rb** (1-2 hours):
- Add compilation for [:bignum_alloc, string] nodes
- Generate code to create heap integer at compile time
- Similar to how string literals are handled

**Testing Strategy** (MUST be done in this order):

1. **Phase A: S-EXPRESSION ENFORCEMENT FIRST** ⚠️ **MANDATORY**
   - Add hard validation to sexp.rb BEFORE touching tokens.rb
   - Test that s-expressions reject large values:
     - `%s((add 1000000000 1))` → MUST raise error and stop compilation
     - `%s((bitand 2147483648 1))` → MUST raise error and stop compilation
   - Ensure error message is clear and mentions the limit
   - Run make selftest-c - should still pass (no large literals in current code)
   - **DO NOT PROCEED** to Phase B until this works perfectly

2. **Phase B: Remove tokenizer truncation**
   - Audit ALL existing s-expressions for large literals first
     - `grep -r "%s" lib/ compiler*.rb | grep -E "[0-9]{9,}"`
     - Manually verify any hits are < 2^29
   - Update tokens.rb to parse full integers
   - Return [:bignum_literal, string] for values > 2^29
   - Run make selftest-c - should still pass
   - Deliberately test: `%s((add 9223372036854775808 1))` → MUST fail with clear error

3. **Phase C: Parser support for large literals**
   - Add handling for [:bignum_literal, ...] tokens in parser
   - Generate [:bignum_alloc, ...] AST nodes
   - Do NOT compile them yet - just parse
   - Test: `x = 9223372036854775808` should parse without error
   - Run make selftest-c

4. **Phase D: Compiler support for heap integer allocation**
   - Compile [:bignum_alloc, ...] nodes
   - Generate code to create heap integer at runtime
   - Test: `x = 9223372036854775808; puts x > 1000`
   - Run make selftest-c

**Risks & Constraints**:
- 🚨 **ABSOLUTE CONSTRAINT**: S-expressions CANNOT accept heap integers (architectural impossibility)
- ⚠️ **HIGH RISK**: If s-expression validation is not in place, compiler will generate broken assembly
- ⚠️ **MEDIUM RISK**: Bootstrap issues if compiler code uses large literals
- ⚠️ **MEDIUM RISK**: Existing code might assume all literals are immediate values

**Mitigation**:
- **ENFORCE s-expression validation FIRST** - this is non-negotiable
- Test incrementally with make selftest-c after EACH phase
- Audit all s-expressions before removing truncation
- Keep truncation as fallback if severe issues arise
- Document the constraint clearly in sexp.rb comments

**Success Criteria**:
- ✅ Regular Ruby code accepts literals like `9223372036854775808`
- ✅ S-expressions reject literals > 2^29-1 with clear error
- ✅ Heap integer allocation generates correct AST
- ✅ make selftest-c passes
- ✅ Simple test: `x = 9223372036854775808; puts x > 1000` works

**Estimated Effort**: 4-8 hours (critical path - blocks all bignum fixes)

---

#### Step 1.1: Fix bignum_value() Helper (2 hours)
**File**: `rubyspec_helper.rb:534`
**Depends On**: Step 1.0 (Large Integer Literal Support)

**Current Code**:
```ruby
def bignum_value(plus = 0)
  # Real value should be: 0x8000_0000_0000_0000 + plus
  # Using a safe 32-bit value instead
  100000 + plus
end
```

**Fix**:
```ruby
def bignum_value(plus = 0)
  # Create actual heap integer with value 0x8000_0000_0000_0000 + plus
  # This is 2^63 = 9223372036854775808
  base = Integer.new
  # Set limbs to represent 2^63:
  # 2^63 = 2^30 * 2^30 * 2^3 = 1073741824 * 1073741824 * 8
  # In 30-bit limbs: [0, 0, 8]
  base.__set_heap_data([0, 0, 8], 1)

  if plus == 0
    return base
  else
    # Add plus to base (requires working heap integer addition)
    return base + plus
  end
end
```

**Test Plan**:
1. Verify heap integer creation works
2. Test with abs_spec.rb (simplest bignum test)
3. Check make selftest-c (no regressions)

**Expected Gain**: Enables all bignum tests (+0 immediate, sets foundation)

#### Step 1.2: Fix Multi-Limb Comparison (8 hours)
**File**: `lib/core/integer.rb`

**Current Status**: "broken for heap integers" (docs/bignums.md:1448)

**Fix**:
- Rewrite `__cmp` dispatch system
- Ensure `<`, `>`, `<=`, `>=`, `<=>` work for heap integers
- Test each operator individually

**Test Plan**:
1. Create test_heap_comparison.rb
2. Test: [0,0,8] > 1000 (should be true)
3. Test: [0,0,8] < 1000 (should be false)
4. Run comparison_spec.rb
5. Check make selftest-c

**Expected Gain**: +20-30 test cases

#### Step 1.3: Fix Multi-Limb to_s Edge Cases (4 hours)
**File**: `lib/core/integer.rb`

**Current Status**: Mostly working but buggy for large values

**Fix**:
- Debug why large bignums return "1"
- Fix limb iteration in to_s
- Test various radixes (2, 10, 16, 36)

**Test Plan**:
1. Test: [0,0,8].to_s == "9223372036854775808"
2. Test: [0,0,8].to_s(16) == "8000000000000000"
3. Run to_s_spec.rb
4. Check make selftest-c

**Expected Gain**: +7 test cases (to_s_spec.rb)

**Phase 1 Total**: +27-37 test cases → 23-25% pass rate
**Effort**: ~14 hours

### Phase 2: Type Coercion (Week 2)

#### Step 2.1: Add Type Checking to Operators (3 hours)
**Files**: `lib/core/integer.rb` (operators: &, |, ^, <<, >>)

**Pattern** (from DEBUGGING_GUIDE.md:230):
```ruby
def & other
  if other.is_a?(Integer)
    other_raw = other.__get_raw
    %s(__int (bitand (callm self __get_raw) other_raw))
  else
    STDERR.puts("TypeError: Integer can't be coerced into Integer")
    nil
  end
end
```

**Apply To**:
- Integer#& (bitwise AND)
- Integer#| (bitwise OR)
- Integer#^ (bitwise XOR)
- Integer#<< (left shift)
- Integer#>> (right shift)

**Test Plan**:
1. Test: 5 & :symbol (should print error, return nil, not crash)
2. Test: 5 & 3 (should work normally)
3. Run bit_and_spec.rb
4. Run left_shift_spec.rb
5. Check make selftest-c

**Expected Gain**: +15-25 test cases

#### Step 2.2: Implement to_int Coercion (4 hours)
**Files**: All arithmetic operators in `lib/core/integer.rb`

**Pattern** (from ceildiv in fixnum.rb):
```ruby
def + other
  # Try to coerce to integer if possible
  if !other.is_a?(Integer) && other.respond_to?(:to_int)
    other = other.to_int
  end

  # Now proceed with normal addition
  # ... existing code ...
end
```

**Apply To**:
- Integer#+ (addition)
- Integer#- (subtraction)
- Integer#* (multiplication)
- Integer#/ (division)
- Integer#% (modulo)

**Test Plan**:
1. Create MockInt with to_int method
2. Test: 5 + MockInt.new(3) == 8
3. Run plus_spec.rb
4. Run multiply_spec.rb
5. Check make selftest-c

**Expected Gain**: +20-30 test cases

#### Step 2.3: Fix Mock Coercion (2 hours)
**File**: `rubyspec_helper.rb`

**Fix**:
- Remove `Mock#__get_raw` workaround
- Add proper `Mock#to_int` method
- Add `Mock#coerce` method

**Test Plan**:
1. Run coerce_spec.rb
2. Check all specs that use Mock objects
3. Check make selftest-c

**Expected Gain**: +5-10 test cases

**Phase 2 Total**: +40-65 test cases → 43-47% pass rate
**Effort**: ~9 hours

### Phase 3: Method Implementation (Week 3)

#### Step 3.1: Implement divmod (3 hours)
**File**: `lib/core/integer.rb`

**Implementation**:
```ruby
def divmod(other)
  quotient = self / other
  remainder = self % other
  [quotient, remainder]
end
```

**For heap integers**:
- Use existing __divmod_by_fixnum for heap / fixnum
- Implement heap / heap if needed

**Test Plan**:
1. Test: 17.divmod(5) == [3, 2]
2. Test: [100].divmod(7) (heap / fixnum)
3. Run divmod_spec.rb
4. Check make selftest-c

**Expected Gain**: +10-20 test cases

#### Step 3.2: Fix Nil Returns (4 hours)
**Investigation**:
1. Find all heap integer methods
2. Audit return values
3. Fix methods returning nil when they should return Integer

**Specific Issues**:
- "Method missing NilClass#__multiply_heap_by_fixnum"
- Check all __multiply_* methods
- Check all __add_* methods

**Test Plan**:
1. Run multiply_spec.rb
2. Run plus_spec.rb
3. Check all arithmetic specs
4. Check make selftest-c

**Expected Gain**: +10-20 test cases

#### Step 3.3: Fix Negative Shift Handling (3 hours)
**File**: `lib/core/integer.rb`

**Current Issues**:
```
left_shift_spec: Expected -1 but got 0 (negative shift)
```

**Fix**:
- n << -m should equal n >> m
- n >> -m should equal n << m
- Handle edge cases correctly

**Test Plan**:
1. Test: 8 << -1 == 4
2. Test: 8 >> -1 == 16
3. Run left_shift_spec.rb
4. Run right_shift_spec.rb
5. Check make selftest-c

**Expected Gain**: +10-15 test cases

**Phase 3 Total**: +30-55 test cases → 52-57% pass rate
**Effort**: ~10 hours

## Overall Impact Projection

| Phase | Effort | Test Cases | Pass Rate | Files Fixed |
|-------|--------|------------|-----------|-------------|
| Baseline | - | 142/747 | 19% | 11/67 |
| After Phase 1 | 14h | 169-179/747 | 23-25% | 13-15/67 |
| After Phase 2 | 23h | 209-244/747 | 28-33% | 18-22/67 |
| After Phase 3 | 33h | 239-299/747 | 32-40% | 23-30/67 |

**Target**: 40% pass rate (300+ test cases) in 3 weeks

## Files Likely to Reach 100%

After implementing all three phases:

**Easy Wins** (already close):
- ✅ abs_spec.rb (1/3 → 3/3)
- ✅ even_spec.rb (4/6 → 6/6)
- ✅ odd_spec.rb (similar to even)
- ✅ magnitude_spec.rb (similar to abs)

**Medium Effort**:
- ✅ to_s_spec.rb (8/15 → 15/15)
- ✅ allbits_spec.rb
- ✅ anybits_spec.rb
- ✅ nobits_spec.rb

**Harder** (need all phases):
- divmod_spec.rb
- comparison_spec.rb
- bit_and_spec.rb (7/18 → 18/18)

## Implementation Notes

### Testing Approach
1. **Always run make selftest-c** after changes
2. **Test incrementally**: One spec at a time
3. **Start simple**: abs_spec → even_spec → to_s_spec → etc.
4. **Document failures**: Update docs/TODO.md with new findings

### Risk Mitigation
- **Backup before Phase 1.2**: Comparison operators are critical
- **Test Phase 2 changes individually**: Don't batch all operators
- **Monitor selftest**: Any regression = stop and debug

### Success Metrics
- **Weekly**: Run full suite, track individual test counts
- **Milestone**: Each phase should show measurable improvement
- **Target**: 40% pass rate = success

## Tools

**Enhanced run_rubyspec**:
```bash
./run_rubyspec rubyspec/core/integer/
```

Now reports:
- File-level pass/fail/segfault
- Individual test case counts
- Pass rate percentage

**Quick single-spec test**:
```bash
./run_rubyspec rubyspec/core/integer/abs_spec.rb
```

**Regression check**:
```bash
make selftest-c
```
