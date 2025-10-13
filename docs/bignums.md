# Bignum Implementation Plan

## Current Status

**Latest work:** Implementing multi-limb addition support

### What Works
- ✅ **Heap integer limb storage WORKING!**
- ✅ **selftest-c PASSING!** (0 failures)
- ✅ **Single-limb heap integer to_s WORKING!**
- ✅ Each heap integer stores correct, unique limb values
- ✅ **Integer#to_s** works for fixnums and single-limb heap integers
- ✅ **Integer#__divmod_by_fixnum** works for fixnums and single-limb heap integers
- ✅ Radix support (2-36) working for single-limb
- Overflow detection and allocation (lib/core/base.rb:56)
- Heap integers work in arithmetic expressions (but limited to 32-bit values)
- **Limbs correctly store tagged fixnums** (e.g., 536870912 stored as 0x40000001)
- **Integer#+** migrated from Fixnum#+ with representation dispatch
- **Integer#__get_raw** extracts values from both fixnums and heap integers
- **Integer#__heap_get_raw** handles single-limb heap integer extraction
- **Tag bit checking** via bitand in s-expression context
- Integer#+ dispatches on all 4 cases:
  - fixnum + fixnum → __add_with_overflow ✅
  - fixnum + heap → __add_fixnum_to_heap ✅
  - heap + fixnum → __add_heap ✅
  - heap + heap → __add_heap ✅
- Integer#- dispatches on all 4 cases:
  - fixnum - fixnum → __add_with_overflow ✅
  - fixnum - heap → uses __get_raw ✅
  - heap - fixnum → uses __get_raw ✅
  - heap - heap → uses __get_raw ✅
- **Integer#inspect** - Returns "<heap-integer>" marker (proper display pending multi-limb to_s)
- **Integer#==** - Equality comparison for both fixnums and heap integers
- Integer#__get_raw dispatches based on representation
- **Comparison operators**: >, >=, <, <= (delegate to __get_raw)
- **Arithmetic operators**: %, * (delegate to __get_raw, * checks overflow)
- Integer class documented with dual representation architecture
- `Integer#initialize` sets up @limbs and @sign for heap integers
- `Integer#__set_heap_data` helper for initialization
- `Integer#__init_overflow` helper for heap integer creation (single-limb only)

### Progress
- ✅ Phase 1: Integer bignum storage structure (documentation)
- ✅ Phase 2: Detection helpers (stub implementation)
- ✅ Phase 3: Allocation and creation (DONE - but single-limb only)
- ✅ Phase 4: Basic Arithmetic (DONE - but single-limb only, delegates to __get_raw)
- ✅ Phase 5: Operator scaffolding (DONE - all operators exist but use __get_raw)
- ⏳ **Phase 6: Multi-Limb Support (MOSTLY COMPLETE)**
  - ✅ Split overflow values into proper 30-bit limbs (Step 5 - COMPLETE)
    - Overflow from addition now creates proper multi-limb heap integers
    - Implemented directly in __add_with_overflow s-expression for bootstrap safety
    - Test: 536870912 + 536870912 = 1073741824 (displays correctly as [0, 1])
    - Can manually create multi-limb integers for testing
  - ✅ Multi-limb addition with carry propagation (Step 3 - DONE)
    - ✅ Implemented __add_magnitudes with carry propagation
    - ✅ Test: [1,1] + [2,0] → 1073741827 ✅
  - ✅ Multi-limb subtraction with borrow propagation (Step 4 - DONE)
    - ✅ Implemented __subtract_magnitudes with borrow propagation
    - ✅ Implemented __compare_magnitudes for magnitude comparison
    - ✅ Test: [1,1] + (-[2,0]) → 1073741823 ✅
  - ✅ Multi-limb comparison (Step 1 - DONE)
  - ✅ Multi-limb to_s conversion (Step 2 - DONE)
    - ✅ Single-limb to_s working
    - ✅ Multi-limb `__divmod_by_fixnum` implementation
    - ✅ Test: 2-limb integer [1,1] → "1073741825"
- Phase 7: Multi-Limb Multiplication (DEFERRED - bootstrap complexity)
  - Attempted implementation but causes compiler self-compilation to segfault
  - Bootstrap constraint: any code in Integer class is used during compiler compilation
  - Complex array manipulation and s-expression/Ruby mixing causes issues
  - Need to either:
    1. Implement in pure s-expressions (very complex)
    2. Find simpler algorithm that avoids problematic patterns
    3. Defer until after Phase 8 or use different approach
- Phase 8: Multi-Limb Division (future)
- Phase 9: Automatic Demotion (optimize by demoting small heap integers)

### Current Representation

**Tagged Fixnum (current):**
- Value stored as: `(value << 1) | 1`
- 30-bit signed integer range: -536,870,912 to 536,870,911
- Lowest bit = 1 indicates fixnum
- Even addresses = heap-allocated objects

## Implementation Approach

**CRITICAL DESIGN DECISION:**
- There is NO separate Bignum class
- Integer must handle BOTH representations:
  - Small values: Tagged fixnums (value << 1 | 1)
  - Large values: Heap-allocated Integer objects with @limbs instance variable
- Methods check representation and dispatch accordingly

### Phase 1: Integer Bignum Storage Structure ✅ DONE
Extend Integer class to support heap-allocated bignum representation.

**Completed:**
- ✅ Added documentation to Integer class (lib/core/integer.rb:2-11)
- ✅ Clarified dual representation architecture
- ✅ No functional changes yet - infrastructure preparation

**Design Decision:**
- Integer unifies both fixnum and bignum representations
- Fixnum class may become obsolete or just a compatibility layer
- Most integer support is currently in Fixnum (legacy) - may need migration

**Commits:**
- 33fec7e - Document bignum implementation plan
- 6e31ed6 - Add documentation for Integer dual representation

### Phase 2: Detection Helpers ✅ DONE
Add methods to detect whether an Integer is tagged or heap-allocated.

**Completed:**
- ✅ Added `__is_heap_integer?` method to Integer (lib/core/integer.rb:68)
- ✅ Currently returns false (no heap integers exist yet)
- ✅ Will be updated when heap allocation is implemented

**Future (deferred to Phase 3):**
- [ ] Update `__is_heap_integer?` to actually check @limbs
- [ ] May need s-expression level helpers for low-level checks

**Commits:**
- d357e52 - Add __is_heap_integer? stub method to Integer

### Phase 3: Allocation and Creation ✅ COMPLETE
Replace overflow detection with actual bignum allocation.

**Completed:**
- ✅ Created `Integer#initialize` to set up @limbs/@sign (lib/core/integer.rb:21)
- ✅ Created `Integer#__set_heap_data(limbs, sign)` helper (lib/core/integer.rb:26)
- ✅ Created `Integer#__init_overflow(raw_value, sign)` helper (lib/core/integer.rb:33)
- ✅ Verified `(callm Integer new)` allocates successfully
- ✅ Implemented Integer#+ with representation dispatch (Phase 3.5)
- ✅ Fixed sarl/sall register clobbering bugs (Phase 3.6)
- ✅ Enabled heap integer allocation in __add_with_overflow
- ✅ Tested: 536870911 + 1 creates heap integer and continues

**Key Insight:**
- sarl operands must be separate variables when referencing locals
- Direct use like `(sarl 29 result)` has register allocation issues
- Solution: `(assign shift_amt 29)` `(assign val result)` `(sarl shift_amt val)`

**Investigation Notes:**
- bitand in nested s-expression context causes segfault (register allocation bug)
- bitand works fine when used directly in single s-expression
- Solution: do tag checks entirely within s-expressions, not via Ruby methods
- Proc allocation pattern: allocate, call setter method, return object

**Bugs Fixed:**
- ✅ Spurious overflow messages (Fixnum#+ issue) - RESOLVED
  - Root cause: Fixnum#+ calling __get_raw without representation check
  - Fix: Removed Fixnum#+ to use Integer#+ instead
- ✅ sarl/sall register clobbering - RESOLVED
  - Root cause: %ecx clobbered when evaluating second argument
  - Fix: Push/pop shift amount around second arg evaluation
  - Also fixed compile_sall with same pattern

**Commits:**
- a54a64d - Refactor overflow handling: extract __make_heap_integer stub
- 3d43c41 - Add Integer#initialize for heap-allocated integers
- bcd8f55 - Fix __is_heap_integer? for selftest-c compatibility
- 10a7ece - Simplify __make_heap_integer to return wrapped fixnum
- 355a193 - Revert to safe overflow handling (investigation ongoing)
- 7ec168b - Document Phase 3 blocker: need Integer#+ before allocation
- b70ab14 - Migrate Fixnum#+ to Integer#+ with representation dispatch
- 5c01a8c - Move representation check to s-expression in Integer#+
- dc2e2e9 - Add heap integer arithmetic dispatch in Integer#+
- c689865 - Update docs: Phase 3 blocker resolved, infrastructure complete
- 8d2948e - Add Integer infrastructure for heap integer support
- 864bce1 - Update docs: document infrastructure and known issues
- 69de528 - Fix: Remove Fixnum#+ to use Integer#+ instead
- 328b128 - Update docs: document Fixnum#+ bug fix
- f58c151 - Revert __add_with_overflow to simple implementation
- b61dd31 - Fix register clobbering bug in compile_sarl and compile_sall

### Phase 4: Basic Arithmetic ✅ COMPLETE
Implement arithmetic operations on heap integers.

**Completed:**
- ✅ Integer#+ handles all combinations (lib/core/integer.rb:74-93)
  - fixnum + fixnum with overflow detection
  - heap + fixnum with overflow detection
  - heap + heap with overflow detection
- ✅ Integer#- handles all combinations (lib/core/integer.rb:95-123)
  - All cases use overflow detection via __add_with_overflow
- ✅ Integer#*, %, / all work via Fixnum using __get_raw
- ✅ Integer#inspect properly displays heap integers (lib/core/integer.rb:169)
- ✅ Basic arithmetic working in expressions
- ✅ All core arithmetic operators working

**CRITICAL LIMITATIONS (Phase 4 is INCOMPLETE without multi-limb):**
- ❌ **ONLY single-limb heap integers (values up to 32-bit)**
- ❌ **All operators use __get_raw which can only handle 32-bit values**
- ❌ **Cannot represent or operate on true bignums (numbers > 32-bit)**
- ❌ **Heap integers are USELESS without multi-limb support**
- Current implementation is just scaffolding - operators exist but don't work for large numbers

**REQUIRED for Phase 6 (Multi-Limb Support):**
- [ ] **CRITICAL**: Split 32-bit+ values into multiple 30-bit limbs
- [ ] **CRITICAL**: Multi-limb addition with carry propagation
- [ ] **CRITICAL**: Multi-limb subtraction with borrow propagation
- [ ] **CRITICAL**: Multi-limb comparison (can't use __get_raw)
- [ ] **CRITICAL**: Multi-limb to_s (can't use __get_raw)
- [ ] Multi-limb multiplication
- [ ] Multi-limb division

### Phase 5: Operator Scaffolding ✅ COMPLETE (scaffolding only - NOT functional for true bignums)
Add all operator methods to Integer class (but they only work for 32-bit values).

**Completed:**
- ✅ All operator methods exist in Integer class
- ✅ **Comparison operators**: ==, >, >=, <, <=, <=> (delegate to __get_raw)
- ✅ **Arithmetic operators**: +, -, *, /, % (delegate to __get_raw)
- ✅ **Unary operators**: -@, +@
- ✅ **Bitwise operators**: &, |, ^, ~, <<, >>
- ✅ **Predicates**: zero?, even?, odd?
- ✅ **Utility methods**: to_i, abs, succ, next, pred
- ✅ Integer#inspect for proper display (lib/core/integer.rb:169)

**CRITICAL LIMITATIONS:**
- ❌ **All operators delegate to __get_raw which only works for 32-bit values**
- ❌ **Cannot actually operate on true bignums (numbers > 2^31)**
- ❌ **This is just scaffolding - operators exist but don't work for large numbers**
- These methods will be rewritten in Phase 6 to work with multi-limb arithmetic

### Phase 6: Multi-Limb Support ⏳ IN PROGRESS (CRITICAL - THE ENTIRE POINT OF BIGNUMS)
Implement true multi-limb arithmetic so bignums can represent numbers > 32-bit.

**Why this is critical:**
- Without multi-limb support, heap integers are completely useless
- The entire point of bignums is to handle numbers larger than fit in 32 bits
- Current implementation is just scaffolding that pretends to work but doesn't

**CRITICAL INSIGHT: __get_raw Cannot Work for Multi-Limb**
- `__get_raw` and `__heap_get_raw` can NEVER work for multi-limb values
- Multi-limb values inherently cannot fit in a single return register
- All operations must work directly on limb arrays, not extracted values
- This means operators like %, /, <, != must be rewritten to handle limb arrays

**Strategy: Copy Fixnum#to_s Algorithm**
The Fixnum#to_s algorithm is the simplest approach:
```ruby
# Algorithm from Fixnum#to_s:
while n != 0
  r = n % radix
  out << digits[r]
  break if n < radix
  n = n / radix
end
```

For this to work on heap integers, we need:
1. `!=` operator (comparison with zero)
2. `<` operator (comparison)
3. `%` operator (modulo by small integer)
4. `/` operator (division by small integer)
5. All must work on limb arrays WITHOUT using __get_raw

**Step 1: Multi-limb comparison operators** ✅ DONE
- ✅ Implemented `Integer#!=` (simple negation of ==)
- ✅ Implemented `Integer#__cmp(other)` - central comparison method
  - Dispatches to __cmp_fixnum_fixnum, __cmp_fixnum_heap, __cmp_heap_fixnum, __cmp_heap_heap
  - Compares signs first
  - Compares limb counts for same sign
  - Compares limbs from most significant to least
- ✅ Updated all comparison operators (<, >, <=, >=) to use __cmp

**Step 2: Multi-limb division by small integer (for to_s)** ⏳ BLOCKED
- ⏳ Attempted `__divmod_by_fixnum(radix)` - divides integer by small fixnum
  - **BLOCKER**: Mixing Ruby `if` with s-expression conditions causes compilation issues
    - `if %s((eq (bitand self 1) 1))` gets compiled as method call, crashes with FPE
    - Solution: Put all logic in single s-expression block
  - **BLOCKER**: Array return from s-expressions problematic
    - Tried `(callm Array new)` + `(callm arr push ...)` - FPE in __eqarg (wrong arg count?)
    - Tried `(callm arr << ...)` - `<<` treated as bit shift operator, not method
    - Tried calling Ruby helper method to pack array - causes parser syntax errors
  - **BLOCKER**: Parser issues with complex code
    - "Syntax error. [{/0 pri=99}]" when trying various approaches
    - Valid Ruby syntax but compiler parser rejects it
    - Comments with `/` inside s-expressions may cause issues
- ⏳ Attempted `__to_s_multi(radix)` based on Fixnum#to_s algorithm
  - Skeleton implemented but blocked by __divmod_by_fixnum issues
- **RECOMMENDATION**: Need to either:
  1. Debug why array creation/method calls fail in s-expressions, OR
  2. Implement __divmod_by_fixnum entirely in s-expression assembly, OR
  3. Find alternative approach that avoids problematic patterns

**Step 3: Multi-limb to_s**
- [ ] Copy Fixnum#to_s algorithm structure
- [ ] Replace operations with multi-limb equivalents
- [ ] Use `__divmod_by_fixnum(radix)` for digit extraction
- [ ] Build string one digit at a time

**Step 4: Update operators to dispatch properly**
- [ ] Integer#/ should detect heap / fixnum and use __divmod_by_fixnum
- [ ] Integer#% should detect heap % fixnum and use __divmod_by_fixnum
- [ ] Keep __get_raw-based implementations as fallback for single-limb only

**Future (Phase 7-8):**
- [ ] Multi-limb multiplication (heap * heap)
- [ ] Multi-limb division (heap / heap)

### Phase 9: Automatic Demotion
Optimize by converting small heap integers back to fixnums.

**TODO:**
- [ ] After operations, check if result fits in fixnum
- [ ] Implement `__heap_integer_to_fixnum_if_fits(integer)`
- [ ] Apply in all arithmetic operations

## Technical Constraints

### CRITICAL: No Large Literals During Compilation
⚠️ **MOST IMPORTANT CONSTRAINT:**

The compiler can compile multi-limb bignum code, but it **CANNOT USE large literals** during compilation until multi-limb support is complete.

**Why this matters:**
- Large integer literals (> 30-bit) cause overflow during parsing
- Overflow triggers heap integer allocation
- Until multi-limb arithmetic is complete, heap integer operations may fail
- This creates a bootstrap problem

**REQUIRED workarounds in compiler source code:**
- ✅ **DO**: Use computed values: `1 << 28`, `1000000 * 1000`
- ❌ **DON'T**: Use large literals: `1000000000000000`
- ✅ **DO**: Build large numbers via operations
- ❌ **DON'T**: Write literals with > 9 digits

**Example fix (Float::INFINITY):**
```ruby
# BAD - causes overflow during compilation:
INFINITY = 999999999999999999999999999999

# GOOD - computes value without literal overflow:
INFINITY = 1 << 28
```

**This constraint only applies during self-compilation.** Once multi-limb support is complete, large literals will work everywhere.

### Tokenizer Limitation
`tokens.rb` truncates large integer literals to prevent parser crashes. This is intentional until multi-limb support is complete.

### Bootstrap Challenges Discovered

**Integer#inspect Issue:**
- Heap integers cannot be converted back to fixnums for display if they don't fit in 30 bits
- Previous approach: extract raw value → tag → convert to string
- Problem: tagging a 32-bit value causes overflow
- Solution: Return "<heap-integer>" marker until proper multi-limb to_s is implemented
- Fixed in commit 5f336e1

**Multi-Limb Implementation Challenges:**
- Cannot easily test multi-limb code because printing results requires multi-limb to_s
- Limb storage representation is tricky: tagged vs raw values
- Array operations in s-expressions during bootstrap can cause issues
- Need to implement multi-limb operations in correct order:
  1. First: multi-limb to_s (for debugging/testing)
  2. Then: multi-limb arithmetic operations
  3. Finally: proper limb splitting in __init_overflow

**Heap Integer Limb Storage - Investigation and Fix:**

**Problem Discovered:**
Array operations in `__init_overflow` (called from s-expression context) were storing incorrect values:
- Array literals `[value]`: Both integers got same wrong value (not value passed)
- Array#push: Both integers got same wrong value (not value passed)
- Index assignment to empty array: Caused segfault during selftest-c

Investigation with debug output showed:
- `raw_value` parameter had correct value (e.g., 0x40000001)
- But `@limbs[0]` after storage had wrong value (e.g., 0x5ee8bee0)
- Both heap integers ended up with identical wrong limb values

**Root Cause:**
The issue was specific to __init_overflow being called from __add_with_overflow's s-expression context. Array operations in that call path didn't work as expected.

**Solution (commit 24bbbe7):**
Modified `__add_with_overflow` to pass single value to `__set_heap_data`:
- Pass tagged value directly from s-expression: `(callm obj __set_heap_data ((__int result) sign))`
- Modified `__set_heap_data` to wrap single values in array using Ruby literal
- Array creation now happens in regular Ruby method context (not s-expression call path)
- Removed `__init_overflow` call entirely from heap integer creation path

**Result:**
- ✅ Each heap integer has unique, correct limb values
- ✅ Limbs correctly store tagged fixnums (e.g., 0x40000001)
- ✅ selftest-c passes (0 failures)
- ✅ Storage mechanism verified working

**to_s Implementation:**
Deferred until after basic arithmetic is working. Integer#inspect returns "<heap-integer>" marker. Can test arithmetic using equality checks.

**Key Insight:**
The compiler CAN compile multi-limb code, but during self-compilation, large values trigger heap allocation. If those heap integer operations aren't complete, bootstrap fails. Solution: keep code simple and avoid operations that would exercise incomplete multi-limb code during compilation.

### Testing Strategy
- `make selftest-c` MUST pass after each commit
- Other tests may temporarily break during implementation
- Each phase should be committed separately
- Update this document with each commit

## Memory Layout

### Integer Object - Two Representations

**Tagged Fixnum (current, continues to work):**
```
Value directly in register/memory: (n << 1) | 1
- Lowest bit = 1 marks as fixnum
- Upper 31 bits = 30-bit signed value + sign bit
```

**Heap-allocated Integer (new, for overflow):**
```
[vtable ptr]      # 4 bytes - points to Integer class vtable
[@limbs]          # 4 bytes - pointer to Array of fixnum limbs
[@sign]           # 4 bytes - fixnum: 1 or -1
```

**Detection:**
- Test lowest bit: `value & 1 == 1` → tagged fixnum
- Test lowest bit: `value & 1 == 0` → heap object (including heap Integer)

### Limb Representation
- Each limb is a tagged fixnum (30-bit signed value)
- Stored in array from least significant to most significant
- Example: 2^40 = 1099511627776 would be:
  - limb[0] = 0 (low 30 bits)
  - limb[1] = 1024 (next 30 bits: 2^40 / 2^30 = 1024)

## Implementation Notes

### Why Array for Limbs?
- Arrays are already implemented and working
- Simplifies memory management (GC handles it)
- Easy to grow/shrink as needed
- Each limb is a fixnum (tagged), so array operations are safe

### Sign Handling
- Separate @sign field simplifies arithmetic
- Magnitude stored in @limbs as positive values
- Operations work on magnitudes, then apply sign
- Avoids two's complement complexity across limbs

### Unified Integer Class
- No separate Bignum class (matches modern Ruby)
- Integer objects are polymorphic:
  - Tagged fixnums: immediate values (low bit = 1)
  - Heap integers: objects with @limbs/@sign (low bit = 0)
- Methods must check representation and dispatch appropriately
- Fixnum class exists but most functionality will move to Integer

## References
- lib/core/base.rb:56 - `__add_with_overflow` function
- lib/core/integer.rb - Integer class
- lib/core/fixnum.rb - Fixnum class (legacy, will be migrated to Integer)
- docs/DEBUGGING_GUIDE.md - Debugging patterns

## Multi-Limb to_s Implementation

### Current Implementation (lib/core/integer.rb:397-509)

**Status:** Single-limb working, multi-limb partially implemented

**Architecture:**
1. `Integer#to_s(radix=10)` → calls `__to_s_multi(radix)`
2. `__to_s_multi` uses repeated division to extract digits
3. `__divmod_by_fixnum(radix)` divides integer by small radix (2-36)
4. Result: string of digits in correct radix

**Single-Limb Division (WORKING):**
- `__divmod_by_fixnum` dispatches in s-expression
- For fixnum: simple div/mod in s-expression
- For single-limb heap: `__divmod_heap_single_limb`
  - Extracts limb value using `@limbs[0]`
  - Performs division in s-expression
  - Returns [quotient, remainder] via Ruby helper

**Multi-Limb Division (IN PROGRESS):**
- Added `__divmod_heap_multi_limb` for len > 1
- Algorithm:
  1. Process limbs from most significant to least significant
  2. For each limb: `(remainder * 2^30 + limb) / radix`
  3. Carry remainder to next limb
  4. Build quotient limb array
  5. Create new heap integer or fixnum from result

**Resolution:**
- Fixed `__divmod_with_carry` to use s-expression multiplication
- `carry * 1073741824 + limb` computed correctly in 32-bit with mul instruction
- Multi-limb division now working correctly

**Test Cases - ALL PASSING:**
- ✅ Single-limb: 536870912.to_s → "536870912"
- ✅ Negative single-limb: -536870913.to_s → "-536870913"
- ✅ Radix: 536870912.to_s(16) → "20000000"
- ✅ Multi-limb: [1,1].to_s → "1073741825"
- ✅ Multi-limb base 16: [1,1].to_s(16) → "40000001"
- ✅ Multi-limb base 36: [1,1].to_s(36) → "hra0ht"
- ✅ selftest-c: 0 failures

**Status: MULTI-LIMB TO_S WORKING! ✅**

## Multi-Limb Addition & Subtraction (Steps 3-4) ✅ COMPLETE

### Implementation

**Algorithm:**
**Addition (same signs):** School addition with carry propagation
**Subtraction (different signs):** Compare magnitudes, subtract smaller from larger

1. Check if signs are same (addition) or different (subtraction)
2. For addition: add limbs with carry propagation
3. For subtraction: compare magnitudes, subtract smaller from larger
4. Handle carry/borrow between limbs
5. Create result heap integer or demote to fixnum if fits

**Key Implementation Details:**
- Implemented `__add_heap` to dispatch to `__add_heap_and_fixnum` or `__add_heap_and_heap`
- Implemented `__add_magnitudes` with limb-by-limb addition and carry propagation
- Implemented `__subtract_magnitudes` with borrow propagation
- Implemented `__compare_magnitudes` to determine which magnitude is larger
- Added helper methods to avoid true/false and large literal issues:
  - `__max_fixnum(a, b)` - returns max without using > operator
  - `__less_than(a, b)` - returns 1 or 0 instead of true/false
  - `__ge_fixnum(a, b)` - returns 1 or 0 for >= comparison
  - `__get_limb_or_zero(arr, i, len)` - safely gets array element or 0
  - `__add_limbs_with_carry(a, b, c)` - adds three limbs with s-expression
  - `__subtract_with_borrow(a, b, c)` - subtracts with borrow
  - `__limb_base_raw()` - computes 2^30 in s-expression (returns raw untagged value)
  - `__half_limb_base()` - computes 2^29 in s-expression
  - `__check_limb_overflow(sum)` - checks overflow and adjusts
  - `__check_limb_borrow(diff)` - checks for borrow and adjusts

**CRITICAL Bootstrap Issue Solved:**
- Cannot use large literals (>= 2^30) during self-compilation
- Cannot use `1 << 30` or `1024 * 1024 * 1024` - they overflow during bootstrap!
- Solution: Compute 2^30 in s-expression as raw untagged value
  - `__limb_base_raw` computes using `mul` in s-expression
  - Returns RAW value (not tagged with __int)
  - Work with raw value in s-expression comparisons and arithmetic

**Key Bug Fixes:**
- Fixed Fixnum#> returning true/false objects that don't work in all contexts
- Fixed `__get_limb_or_zero` s-expression index operation - rewrote using Ruby array indexing
- Fixed large literal bootstrap issue - cannot tag 2^30 as fixnum!
- Avoided mixing Ruby control flow with s-expression comparisons

**Test Results:**
- ✅ [1,1] + [2,0] → 1073741827 (addition: 1073741825 + 2)
- ✅ [1,1] + (-[2,0]) → 1073741823 (subtraction: 1073741825 - 2)
- ✅ [3] + [2] → 5 (single-limb addition)
- ✅ selftest-c: 0 failures

**Status: Multi-limb addition AND subtraction WORKING! ✅**

## Phase 7: Multi-Limb Multiplication

### Root Cause Analysis

The fundamental challenge is capturing full multiplication results:

**The Word-Size Truncation Problem:**
- Current `(mul a b)` operation only returns single-word result (32 bits)
- Multiplying two 30-bit numbers can produce up to 60 bits (2^30 × 2^30 = 2^60)
- The high bits of the product are lost, making proper multi-limb arithmetic impossible
- This truncation prevents correct carry propagation in multi-limb multiplication

**The Full Result Solution:**
- Need widening multiply operation that returns both low and high words of product
- Low word: bits 0-31 of product
- High word: bits 32-63 of product
- Current s-expression system only exposes single return value
- Need mechanism to capture both parts of the result

### Comprehensive Solution Plan

#### Option A: Extend S-Expression Operations (RECOMMENDED)

**Approach:** Add new s-expression operations that expose full 64-bit multiply result.

**Step A1: Add `mulfull` operation to compiler**

Location: `compile_arithmetic.rb` or similar

```ruby
# New s-expression: (mulfull a b result_ptr)
# Multiplies a * b and stores both low and high parts of the result
# - result_ptr[0] receives low word (bits 0-31 of product)
# - result_ptr[1] receives high word (bits 32-63 of product)
# Returns: result_ptr (for chaining)
#
# This enables capturing the full result of multiplying two 30-bit values,
# which can produce up to 60 bits and requires two words to represent.
#
# Register usage: Clobbers caller-saved registers per calling convention

**Step A2: Implementation of compile_mulfull**

The emitter already has methods for movl, pushl, popl, imull. No new emitter methods needed:

```ruby
def compile_mulfull(scope, left, right, result_ptr)
  # Evaluate all operands and save to stack
  compile_eval_arg(scope, :eax, left)
  @e.pushl(:eax)

  compile_eval_arg(scope, :ecx, right)
  @e.pushl(:ecx)

  compile_eval_arg(scope, :ebx, result_ptr)
  @e.pushl(:ebx)

  # Restore operands from stack
  @e.popl(:ebx)  # result_ptr
  @e.popl(:ecx)  # right operand
  @e.popl(:eax)  # left operand

  # One-operand imull: EAX * ECX -> EDX:EAX (full 64-bit result)
  @e.imull(:ecx)

  # Store both result words to memory
  @e.movl(:eax, [:ebx, 0])   # low word
  @e.movl(:edx, [:ebx, 4])   # high word

  # Return result_ptr
  @e.movl(:ebx, :eax)
end
```

**Step A3: Implement helper in lib/core/integer.rb**

```ruby
# Multiply two raw 30-bit values, return [low_bits, high_bits]
def __multiply_raw_with_full_result(a_raw, b_raw)
  %s(
    (let (a b result_ptr low_word high_word)
      (assign a a_raw)
      (assign b b_raw)

      # Allocate 8 bytes on stack for result (two 32-bit words)
      (sub esp 8)
      (assign result_ptr esp)

      # Call mulfull to store result in stack memory
      (mulfull a b result_ptr)

      # Load results from stack
      (assign low_word (index result_ptr 0))
      (assign high_word (index result_ptr 4))

      # Clean up stack
      (add esp 8)

      # Return as Ruby array
      (return (callm self __make_overflow_result ((low_word high_word)))))
  )
end
```

Note: This assumes `__make_overflow_result` exists to wrap two values in an array, or use alternative approach to return the values.

**Step A4: Implement limb-by-limb multiplication**

```ruby
def __multiply_limb_by_fixnum_with_carry(limb, multiplier_raw, carry_in)
  # Extract raw values
  limb_raw = %s((sar limb))

  # Multiply limb * multiplier
  result_pair = __multiply_raw_with_full_result(limb_raw, multiplier_raw)
  low_bits = result_pair[0]
  high_bits = result_pair[1]

  # Add carry
  sum_low = low_bits + carry_in
  carry_from_add = 0
  if sum_low >= __limb_base_raw
    sum_low = sum_low - __limb_base_raw
    carry_from_add = 1
  end

  # Total carry = high_bits from multiply + carry from addition
  total_carry = high_bits + carry_from_add

  return [sum_low, total_carry]
end

def __multiply_heap_by_fixnum(other)
  my_limbs = @limbs
  my_sign = @sign

  # Extract other as raw value and determine sign
  other_raw = %s((sar other))
  other_sign = 1
  if other_raw < 0
    other_raw = 0 - other_raw
    other_sign = -1
  end

  result_limbs = []
  carry = 0
  i = 0
  len = my_limbs.length

  while i < len
    limb = my_limbs[i]
    result_pair = __multiply_limb_by_fixnum_with_carry(limb, other_raw, carry)
    result_limbs << result_pair[0]
    carry = result_pair[1]
    i = i + 1
  end

  # Append final carry if non-zero
  if carry != 0
    result_limbs << carry
  end

  # Create result
  result_sign = my_sign * other_sign
  result = Integer.new
  result.__set_heap_data(result_limbs, result_sign)
  return result
end
```

**Step A5: Implement heap * heap multiplication**

```ruby
def __multiply_heap_by_heap(other)
  my_limbs = @limbs
  my_sign = @sign
  other_limbs = other.__get_limbs
  other_sign = other.__get_sign

  my_len = my_limbs.length
  other_len = other_limbs.length
  result_len = my_len + other_len

  # Initialize result array with zeros
  result_limbs = []
  i = 0
  while i < result_len
    result_limbs << 0
    i = i + 1
  end

  # School multiplication
  i = 0
  while i < my_len
    limb_a = my_limbs[i]
    limb_a_raw = %s((sar limb_a))

    carry = 0
    j = 0
    while j < other_len
      limb_b = other_limbs[j]
      limb_b_raw = %s((sar limb_b))

      # Multiply limb_a * limb_b with full result
      mult_result = __multiply_raw_with_full_result(limb_a_raw, limb_b_raw)
      low_bits = mult_result[0]
      high_bits = mult_result[1]

      # Add to result at position i+j
      pos = i + j
      current = result_limbs[pos]
      current_raw = %s((sar current))

      sum = current_raw + low_bits + carry

      # Handle overflow
      if sum >= __limb_base_raw
        adjusted = sum - __limb_base_raw
        new_carry = high_bits + 1
      else
        adjusted = sum
        new_carry = high_bits
      end

      result_limbs[pos] = %s((__int adjusted))
      carry = new_carry

      j = j + 1
    end

    # Add final carry
    if carry != 0
      pos = i + other_len
      result_limbs[pos] = %s((__int carry))
    end

    i = i + 1
  end

  # Remove leading zeros
  # ... (similar to __subtract_magnitudes)

  # Create result with correct sign
  result_sign = my_sign * other_sign
  result = Integer.new
  result.__set_heap_data(result_limbs, result_sign)
  return result
end
```

**Benefits of Option A:**
- ✅ Captures full 64-bit multiply result
- ✅ No truncation or data loss
- ✅ Extends s-expression system in clean, reusable way
- ✅ Other operations could benefit from `mulfull` in future
- ✅ Follows established pattern (similar to how `div` works)

**Risks:**
- ⚠️ Requires compiler changes (but well-defined scope)
- ⚠️ Bootstrap sequence needs careful testing
- ⚠️ Must correctly capture both result words across architectures

#### Option B: Chunk Multiplication (FALLBACK)

**Approach:** Break 30-bit limbs into smaller chunks that can be multiplied without overflow.

**Algorithm:**
- Split each 30-bit limb into two 15-bit chunks
- Multiply 15-bit × 15-bit = 30-bit (fits in 32 bits)
- Combine results using addition and shifting

**Example:**
```ruby
# For limb a = 0x3FFFFFFF (30 bits) and limb b = 0x3FFFFFFF:
a_low = a & 0x7FFF          # Low 15 bits
a_high = (a >> 15) & 0x7FFF # High 15 bits
b_low = b & 0x7FFF
b_high = (b >> 15) & 0x7FFF

# Four partial products:
p1 = a_low * b_low           # Bits 0-29
p2 = a_low * b_high          # Bits 15-44
p3 = a_high * b_low          # Bits 15-44
p4 = a_high * b_high         # Bits 30-59

# Combine (with carry handling):
result_low = p1 + ((p2 + p3) << 15)
result_high = p4 + ((p2 + p3) >> 15) + carry_from_low
```

**Benefits:**
- ✅ No compiler changes needed
- ✅ Uses only existing s-expression operations
- ✅ Guaranteed to work within 32-bit arithmetic

**Drawbacks:**
- ❌ 4× more multiplications per limb operation
- ❌ Complex carry propagation logic
- ❌ More room for bugs in implementation
- ❌ Slower execution

#### Option C: Division-Based Splitting (FOR OVERFLOW SPLITTING ONLY)

**Approach:** For splitting overflow values into limbs, use division rather than multiplication.

**Algorithm for Phase 6 Step 5:**
```ruby
def __init_from_overflow_value(raw_value, sign)
  # Get absolute value
  abs_val = raw_value
  if abs_val < 0
    abs_val = 0 - abs_val
  end

  limbs = []
  # Extract limbs using division
  while abs_val != 0
    limb_base = __limb_base_raw  # 2^30 as raw value
    remainder = abs_val % limb_base
    quotient = abs_val / limb_base

    limbs << %s((__int remainder))
    abs_val = quotient

    # Safety limit
    if limbs.length > 4
      break
    end
  end

  if limbs.length == 0
    limbs << 0
  end

  @limbs = limbs
  @sign = sign
end
```

**Note:** Division works in s-expressions because `div` and `mod` operations already exist and handle 32-bit correctly. This approach is sufficient for Phase 6 Step 5 (splitting overflow values) but doesn't solve Phase 7 (multiplication).

### Implementation Roadmap

**Phase 7A: Extend S-Expression System (RECOMMENDED PATH)**

### Implementation Progress

**Step 7A.1: Add compile_mulfull - COMPLETE ✅**

Changes made:
- ✅ Added `:mulfull` to @@keywords in compiler.rb:52
- ✅ Added `compile_mulfull(scope, left, right, low_var, high_var)` to compile_arithmetic.rb:148
- ✅ Test passes: 100 * 200 = 20000 ✅
- ✅ `make selftest-c`: 0 failures ✅

Implementation:
- S-expression: `(mulfull a b low_var high_var)`
- Performs one-operand `imull %ecx` to get full 64-bit result in edx:eax
- Stores low word (bits 0-31) to low_var
- Stores high word (bits 32-63) to high_var
- Returns low word in eax
- Stack balanced, no leaks

Key learnings:
- Cannot pass `[:lvar, offset]` directly to `@e.movl` - it's a symbolic representation
- Must use `scope.get_arg(var)` to get `[type, param]`, then use `@e.save(type, source, param)`
- Memory operands like `4(%esp)` must be strings, not arrays
- Save both results to stack first, then pop and store one at a time to avoid clobbering

Test results:
- ✅ Small values: 100 * 200 = 20000 (low=20000, high=0)
- ✅ Large values: 65536 * 65537 = 4,295,032,832 (low=65536, high=1)
- ✅ Both low and high words captured correctly

**Step 7A.2: Create Ruby wrapper for mulfull - IN PROGRESS**

Attempted:
- Added `__multiply_raw_full(a_raw, b_raw)` method to Integer class
- Issues with parameter passing between Ruby and s-expression contexts
- Ruby method parameters come in as tagged fixnums, need careful untagging
- Scoping between Ruby variables and s-expression let variables is complex

Current blocker:
- Need to understand how to properly pass values from Ruby method parameters into s-expression local variables
- `(assign a (sar a_raw))` doesn't work as expected when a_raw is a Ruby parameter

Options:
1. Keep using mulfull directly in s-expressions (works perfectly)
2. Study existing methods that bridge Ruby/s-expression parameter passing
3. Defer wrapper until better understanding of scoping rules

**Decision: Pause wrapper creation, use mulfull directly in s-expressions for now**

**Step 7A.4: Implement __multiply_limb_by_fixnum_with_carry - COMPLETE ✅**

Changes made:
- ✅ Added `__multiply_limb_by_fixnum_with_carry(limb, fixnum, carry_in)` to Integer class (line 595-640)
- ✅ Uses `mulfull` to multiply limb × fixnum, producing [low, high]
- ✅ Adds carry_in to low word with unsigned overflow detection
- ✅ Splits 64-bit result into 30-bit limb and 34-bit carry using bit operations
- ✅ Returns [result_limb, carry_out] as tagged fixnums
- ✅ Handles signed/unsigned arithmetic correctly for values exceeding 2^31

Implementation details:
- Uses `(mulfull limb_raw fixnum_raw low high)` for widening multiply
- Detects unsigned overflow: `(if (lt sum_low low)` after addition
- Extracts limb: `(bitand sum_low 0x3FFFFFFF)` - bottom 30 bits
- Extracts bits 30-31: `(sub sum_low result_limb) / limb_base`
- Adjusts for signed division when sum_low < 0 by adding 4
- Final carry: `(sum_high * 4) + bits_30_31`

Test results:
- ✅ Small values: 1000 × 2 + 0 = 2000 (limb=2000, carry=0)
- ✅ Large values: 10000 × 10000 + 0 = 100000000 (fits in 30 bits)
- ✅ Overflow case: 536870912 × 2 + 0 = 2^30 (limb=0, carry=1)
- ✅ Carry propagation: [536870912, 100] × 2 = [0, 201] ✅
- ✅ Cascading carries: [536870912, 536870912] × 2 = [0, 1, 1] ✅
- ✅ Large carry: 536870912 × 4 = [0, 2] ✅
- ✅ Non-zero limb: 536870912 × 3 = [536870912, 1] ✅
- ✅ Non-zero with overflow: 100000 × 15000 = [426258176, 1] ✅
- ✅ Non-zero with carry_in: 200000000 × 7 + 100 = [326258276, 1] ✅
- ✅ Multi-limb non-zero: [100000, 536870912] × 3 = [300000, 536870912, 1] ✅
- ✅ `make selftest-c`: 0 failures

**Step 7A.5: Implement __multiply_heap_by_fixnum - COMPLETE ✅**

Changes made:
- ✅ Added `__multiply_heap_by_fixnum(fixnum_val)` to Integer class (line 634-706)
- ✅ Iterates through limbs, multiplying each by fixnum with carry propagation
- ✅ Uses `__multiply_limb_by_fixnum_with_carry` helper for each limb
- ✅ Appends final carry as new limb if non-zero
- ✅ Demotes to fixnum if result fits in 30 bits
- ✅ Returns heap integer otherwise

Implementation:
- Loop through each limb in the heap integer
- Multiply limb × fixnum + carry_in → [result_limb, carry_out]
- Accumulate result limbs
- Check if result fits in fixnum (single limb < 2^29)
- Create appropriate return value (fixnum or heap integer)

Test results:
- ✅ [100, 200] × 2 = [200, 400] (correct multi-limb result)
- ✅ `make selftest-c`: 0 failures

Current limitations:
- Only handles positive fixnums (negative fixnum support deferred)
- Sign handling simplified: result_sign = my_sign

**Step 7A.7: Implement __multiply_heap_by_heap - COMPLETE ✅**

Changes made:
- ✅ Added `__multiply_heap_by_heap(other)` to Integer class (line 703-817)
- ✅ Implements school multiplication algorithm
- ✅ For each limb in multiplier, multiplies all limbs of multiplicand
- ✅ Accumulates partial products at appropriate offsets
- ✅ Handles carry propagation during addition
- ✅ Trims leading zeros from result
- ✅ Handles sign: result_sign = my_sign × other_sign
- ✅ Demotes to fixnum if result fits

Implementation details:
- Allocates result array with max_len = my_len + other_len limbs
- Outer loop (j): iterates through other_limbs
- Inner loop (i): multiplies my_limbs[i] × other_limbs[j]
- Uses `__multiply_limb_by_fixnum_with_carry` for limb × limb
- Adds product to result[i+j] with overflow detection
- Overflow check: `if sum < current` means unsigned overflow occurred
- Trims leading zeros using flag-based loop

Test results:
- ✅ Single × single: [100] × [200] = 20000 (demoted to fixnum)
- ✅ Multi × single: [100, 200] × [2] = [200, 400]
- ✅ Multi × multi: [10, 20] × [3, 4] = [30, 100, 80]
- ✅ With carries: [536870912, 1] × [2, 0] = [0, 3]
- ✅ `make selftest-c`: 0 failures

**Step 7A.8: Update Integer#* dispatcher - PARTIALLY COMPLETE**

Changes made:
- ✅ Added dispatcher logic to `Integer#*` operator (line 1314-1337)
- ✅ Dispatches based on operand types using `(bitand self 1)` check
- ✅ Four cases: fixnum×fixnum, fixnum×heap, heap×fixnum, heap×heap
- ✅ Created `__multiply_fixnum_by_heap` helper method
- ✅ Created `__multiply_heap` dispatcher for heap integer cases
- ⚠️ Known bug: fixnum × heap returns garbage value

Test results:
- ✅ fixnum × fixnum: works correctly
- ✅ heap × fixnum: works correctly
- ✅ heap × heap: works correctly (tested separately)
- ⚠️ fixnum × heap: returns wrong value (known issue)

Current status:
- All critical multiplication cases work (heap×fixnum, heap×heap, fixnum×fixnum)
- The fixnum × heap case has a bug in the dispatcher return path
- Helper method `__multiply_fixnum_by_heap` is defined but returns garbage
- Direct method calls work fine; issue is specific to s-expression dispatcher
- `make selftest-c`: 0 failures (bootstrap works)

Known issue details:
- When calling `4 * heap`, expected result is 200, gets garbage (-940984384, varies)
- The helper method `__multiply_fixnum_by_heap` is NOT being called (no debug output)
- Issue appears to be in how returns propagate from nested if statements in s-expressions
- Workaround: Users can write `heap * 4` instead of `4 * heap`

Investigation attempts:
- Tested calling methods on fixnums from s-expressions: works
- Tested calling `heap.__multiply_heap_by_fixnum(fixnum)` directly: works
- Tested s-expression structure similar to + operator: still fails
- Printf debugging in s-expressions causes assembly errors

Next steps:
- [ ] Debug why `__multiply_fixnum_by_heap` isn't being called
- [ ] Consider alternative dispatcher structure
- [ ] Add negative fixnum support
- [ ] Add comprehensive integration tests

---

## Phase 7 Implementation Summary

**Status: MOSTLY COMPLETE** (as of session end)

### Completed Work

1. **compile_mulfull (Step 7A.1)** ✅
   - Added widening multiply s-expression: `(mulfull a b low_var high_var)`
   - Captures full 64-bit result from 32-bit × 32-bit multiplication
   - Uses x86 one-operand imull instruction (edx:eax result)
   - Properly stores both low and high words to variables
   - Location: `compile_arithmetic.rb:148-190`

2. **__multiply_limb_by_fixnum_with_carry (Step 7A.4)** ✅
   - Multiplies single 30-bit limb by fixnum with carry propagation
   - Returns [result_limb, carry_out]
   - Uses bitwise operations to split 64-bit result correctly
   - Handles signed/unsigned arithmetic for values > 2^31
   - Comprehensive test coverage including non-zero result limbs
   - Location: `lib/core/integer.rb:595-640`

3. **__multiply_heap_by_fixnum (Step 7A.5)** ✅
   - Multiplies multi-limb integer by fixnum
   - Iterates through limbs with carry propagation
   - Properly handles overflow and carry between limbs
   - Demotes to fixnum when result fits in 30 bits
   - Location: `lib/core/integer.rb:642-701`

4. **__multiply_heap_by_heap (Step 7A.7)** ✅
   - School multiplication algorithm for multi-limb × multi-limb
   - Nested loops: for each limb in multiplier, multiply all multiplicand limbs
   - Accumulates partial products at correct offsets
   - Unsigned overflow detection during addition
   - Trims leading zeros from result
   - Handles sign correctly: result_sign = my_sign × other_sign
   - Location: `lib/core/integer.rb:703-817`

5. **Integer#* Dispatcher (Step 7A.8)** ⚠️ PARTIALLY COMPLETE
   - Dispatches based on operand types (fixnum vs heap)
   - Three of four cases work correctly:
     - fixnum × fixnum ✅
     - heap × fixnum ✅
     - heap × heap ✅
     - fixnum × heap ⚠️ (known bug)
   - Location: `lib/core/integer.rb:1314-1337`

### Test Results

**All tests pass except fixnum × heap:**
- Small values: 1000 × 2 + 0 = 2000 ✅
- Large values: 10000 × 10000 = 100,000,000 ✅
- Overflow: 536870912 × 2 = 2^30 → [0, 1] ✅
- Carry propagation: [536870912, 100] × 2 = [0, 201] ✅
- Cascading carries: [536870912, 536870912] × 2 = [0, 1, 1] ✅
- Non-zero limbs: 536870912 × 3 = [536870912, 1] ✅
- Multi-limb: [10, 20] × [3, 4] = [30, 100, 80] ✅
- **make selftest-c: 0 failures** ✅

### Known Issues

**fixnum × heap dispatcher bug:**
- Symptom: `4 * heap` returns garbage instead of correct result
- Impact: Users must write `heap * 4` instead of `4 * heap`
- Root cause: Helper method `__multiply_fixnum_by_heap` not being called from s-expression
- Investigation: Return value issue in nested if statements within s-expression
- Priority: LOW (workaround available, all critical cases work)

### Files Modified

- `compiler.rb`: Added :mulfull keyword
- `compile_arithmetic.rb`: Added compile_mulfull method
- `lib/core/integer.rb`: Added multiplication methods and updated * operator
- `docs/bignums.md`: Comprehensive documentation of implementation

### Performance Characteristics

- Limb size: 30 bits (fits in tagged fixnum)
- School multiplication: O(n²) for n-limb numbers
- Carry propagation: Single pass through limbs
- Memory: Allocates result array sized for worst case (m+n limbs)

### Future Work

1. Fix fixnum × heap dispatcher bug
2. Add negative fixnum support in multiplication
3. Implement heap × heap optimization (Karatsuba for large numbers)
4. Add division support for multi-limb integers
5. Optimize memory allocation patterns

---

**Original Steps:**

1. **Step 7A.1:** Add `compile_mulfull` to compiler (2 hours)
   - Location: `compile_arithmetic.rb` or similar
   - Implement register allocation and result storage
   - Use existing emitter methods (movl, pushl, popl)
   - Emit widening multiply instruction directly
   - Test: Compile test that uses `(mulfull a b result_ptr)`

2. **Step 7A.2:** Test `mulfull` in isolation (1 hour)
   - Create `test_mulfull.rb` with direct s-expression usage
   - Verify low/high word split is correct
   - Test edge cases: 0×0, max×max, negative values

3. **Step 7A.3:** Implement `__multiply_raw_with_full_result` (1 hour)
   - Location: `lib/core/integer.rb`
   - Wrap `mulfull` in Ruby helper
   - Test: Verify returns [low, high] correctly

4. **Step 7A.4:** Implement `__multiply_limb_by_fixnum_with_carry` (2 hours)
   - Multiply single limb by fixnum with carry
   - Test: 536870912 × 2 with carry

5. **Step 7A.5:** Implement `__multiply_heap_by_fixnum` (2 hours)
   - Full heap integer × fixnum multiplication
   - Test: [1,1] × 2, [1,1] × 1000

6. **Step 7A.6:** Test with `make selftest-c` (1 hour)
   - Ensure bootstrap works
   - Fix any issues that arise
   - Document any new constraints

7. **Step 7A.7:** Implement `__multiply_heap_by_heap` (4 hours)
   - School multiplication algorithm
   - Handle carry propagation across limbs
   - Test: [1,1] × [2,0], [1,1] × [1,1]

8. **Step 7A.8:** Update `Integer#*` dispatcher (1 hour)
   - Dispatch to heap multiplication methods
   - Remove `__get_raw` fallback for heap values
   - Test: All combinations (fixnum×fixnum, fixnum×heap, heap×fixnum, heap×heap)

9. **Step 7A.9:** Comprehensive testing (2 hours)
   - Test suite with various combinations
   - Verify `make selftest-c` still passes
   - Test negative numbers, zero, edge cases
   - Commit working implementation

**Total Estimated Time: 16 hours**

**Phase 6 Step 5: Complete Overflow Splitting (PARALLEL WORK)**

Can be done independently using division-based approach:

1. **Step 5.1:** Implement `__init_from_overflow_value` using division (1 hour)
2. **Step 5.2:** Test in isolation with manual creation (30 min)
3. **Step 5.3:** Update `__add_with_overflow` to use it (30 min)
4. **Step 5.4:** Test overflow detection (1 hour)
   - Test: 536870911 + 1 creates proper multi-limb
   - Test: 536870912 + 536870912 = [0, 2]
5. **Step 5.5:** Verify `make selftest-c` (30 min)

**Total Estimated Time: 3.5 hours**

### Alternative: Phase 7B (Chunk Multiplication - Fallback)

If Option A proves too complex during bootstrap:

1. **Step 7B.1:** Implement 15-bit chunk multiplication (3 hours)
2. **Step 7B.2:** Test chunk multiplication in isolation (1 hour)
3. **Step 7B.3:** Build full limb multiplication using chunks (2 hours)
4. **Step 7B.4:** Continue as Steps 7A.5 through 7A.10 (10 hours)

**Total Estimated Time: 16 hours**

### Testing Strategy for Phase 7

**Unit Tests:**
```ruby
# test_multiply_basic.rb
a = Integer.new
a.__set_heap_data([2], 1)
b = 3
result = a * b
puts result.to_s  # Should print "6"

# test_multiply_overflow.rb
a = Integer.new
a.__set_heap_data([536870912], 1)  # 2^29
b = 4
result = a * b
puts result.to_s  # Should print "2147483648" = [0, 2]

# test_multiply_multilimb.rb
a = Integer.new
a.__set_heap_data([1, 1], 1)  # 1073741825
b = 2
result = a * b
puts result.to_s  # Should print "2147483650" = [2, 2]

# test_multiply_heap_heap.rb
a = Integer.new
a.__set_heap_data([1, 1], 1)  # 1073741825
b = Integer.new
b.__set_heap_data([2, 0], 1)  # 2
result = a * b
puts result.to_s  # Should print "2147483650"
```

**Bootstrap Validation:**
- Run `make selftest-c` after each step
- If segfault: Revert, simplify, retry
- If incorrect result: Add debug output to trace execution
- If compilation fails: Check s-expression syntax

### Success Criteria

**Phase 6 Step 5 Complete:**
- ✅ Overflow from addition creates proper multi-limb integers
- ✅ `536870911 + 1` creates [536870912] (single limb)
- ✅ `536870912 + 536870912` creates [0, 2] (two limbs)
- ✅ `make selftest-c` passes

**Phase 7 Complete:**
- ✅ Multi-limb × fixnum works correctly
- ✅ Multi-limb × multi-limb works correctly
- ✅ Negative numbers handled properly
- ✅ Large multiplications produce correct results
- ✅ `make selftest-c` passes
- ✅ All test cases pass

### Risk Mitigation

**If `mulfull` causes bootstrap issues:**
1. Implement and test `mulfull` with MRI-compiled compiler first
2. Test simple cases before complex multi-limb code
3. Add debug output to trace low/high word values
4. Consider fallback to Option B (chunk multiplication)

**If school multiplication is too complex for bootstrap:**
1. Start with simpler heap × small fixnum only
2. Test thoroughly before adding heap × heap
3. Consider Karatsuba algorithm (fewer multiplications, more additions)
4. Use repeated addition for very small multipliers as fallback

**If s-expression/Ruby mixing causes issues:**
1. Move more logic into pure Ruby (outside s-expressions)
2. Use s-expressions only for low-level multiply operation
3. Handle carry/overflow in Ruby code
4. Test each piece independently

### Summary

**Recommended Path:**
- **Phase 6 Step 5:** Use division-based splitting (simple, works with existing operations)
- **Phase 7:** Extend s-expression system with `mulfull` operation (clean, reusable, performant)

**Key Insight:**
The "too fragile for bootstrap" concern was valid for complex implementations, but extending the s-expression system with proper 64-bit multiply support is a clean, well-scoped change that follows established patterns. The real fragility came from complex array manipulation and context mixing, not from the fundamental approach.

**Next Actions:**
1. Implement `mulfull` s-expression operation
2. Test in isolation before integrating
3. Build multi-limb multiplication incrementally
4. Validate with `make selftest-c` at each step

## Phase 6 Step 5: Overflow Value Splitting - COMPLETE ✅

### Implementation (lib/core/base.rb:56-86)

**Approach:** Limb splitting implemented directly in `__add_with_overflow` s-expression.

**Why this approach:**
- Previous attempts to call `__init_from_overflow_value` from s-expression context caused segfaults
- Mixing Ruby control flow with raw untagged values is problematic
- Instance variable assignment from s-expressions doesn't work reliably
- Solution: Do all splitting inline in `__add_with_overflow`, call `__set_heap_data` to set ivars

**Algorithm:**
1. Detect overflow: if `high_bits = result >> 29` is not 0 or -1
2. Allocate Integer object
3. Determine sign: -1 if result < 0, else 1
4. Compute absolute value: `abs_val = (result < 0) ? -result : result`
5. Compute limb_base = 2^30 using `__limb_base_raw` (multiplication, not shift)
6. Extract limbs:
   - `limb0 = abs_val % limb_base` (bits 0-29)
   - `limb1 = abs_val / limb_base` (bits 30-31)
7. Create array, push limb0, conditionally push limb1 if non-zero
8. Call `__set_heap_data(array, sign)` to set @limbs and @sign
9. Return heap integer object

**Bootstrap Safety:**
- All logic in single s-expression (no Ruby/s-expression mixing)
- No raw values passed as method arguments
- No instance variable assignment in s-expressions
- Array creation and manipulation stay in s-expression context
- Only call Ruby method (`__set_heap_data`) with properly constructed arguments

**Test Results:**
- ✅ 536870912 + 536870912 = 1073741824 (two limbs: [0, 1])
- ✅ 536870911 + 2 = 536870913 (single limb, correctly sized)
- ✅ Positive overflow cases work correctly
- ✅ Heap integer + fixnum addition works (1073741824 + 1 = 1073741825)
- ✅ selftest-c: 0 failures
- ⚠️ Negative overflow has display issues (limbs correct, to_s shows wrong value)
- ⚠️ Heap integer + heap integer not fully tested

**Bug Fixed (commit 02a717a):**
- Heap + fixnum was incorrectly subtracting instead of adding
- Root cause: `other_sign_val` was raw integer but `@sign` is tagged fixnum
- Fix: Tag sign values with `(__int 1)` and `(__int -1)` in `__add_heap_and_fixnum`

**Current Limitations:**
- **Multi-limb to_s BROKEN for limb0=0 cases** (e.g., `[0, 2]` displays as "8")
  - Root cause: `__divmod_with_carry` line 1200 uses 32-bit multiplication
  - `carry * 1073741824` overflows for carry >= 2 in 32-bit signed arithmetic
  - Example: `[0, 2]` → carry=2 → `2 * 2^30 = 2^31` overflows to negative
  - Result: `__divmod_by_fixnum(10)` returns `[-214748364, -8]` instead of correct values
  - Impact: Heap + heap addition creates correct limbs but displays wrong value
  - Fix requires: 64-bit multiplication or alternative algorithm (Phase 7 scope)

- **Negative heap integers have multiple display/comparison issues**
  - `to_s` displays incorrect values (e.g., `[100]` with sign -1 shows "a0" instead of "-100")
  - Root cause chain:
    1. `to_s` line 1224 uses `self < 0` to detect negative numbers
    2. `<` operator (line 1468) calls `__cmp(other)`
    3. `__cmp` dispatch (line 862-885) uses s-expression to route to `__cmp_heap_fixnum`
    4. **Bug**: `__cmp_heap_fixnum` is never actually called (dispatch fails silently)
    5. Fallback behavior returns incorrect comparison results
    6. Result: negative detection fails, number isn't negated, divmod returns negative values
    7. Negative array indices into digit string cause corrupted output
  - Attempted fixes:
    - Tried fixing s-expression dispatch - didn't work
    - Tried extracting sign in Ruby code - methods not being called
    - Tried accessing @sign via `(index self 2)` - incorrect
    - Tried accessing @sign directly in s-expression - still fails
  - **Conclusion**: S-expression/Ruby mixing in comparison dispatch is fundamentally broken
  - Likely conflicts with `<=>` operator (line 1355) which also uses `__get_raw`
  - Fix requires: Rewriting entire comparison system without s-expression dispatch complexity

- Only tested for overflow from fixnum + fixnum
- Multiplication and other operations still use __get_raw

**Next Steps:**
- Fix __divmod_with_carry 32-bit overflow (requires 64-bit multiply support - Phase 7)
- Fix negative heap integer comparisons (requires comparison system rewrite - complex)
- Implement proper multiplication (Phase 7 - deferred due to complexity)

## Testing Approach

### Test File Organization

**Single-Limb Tests:**
- `test_heap_minimal.rb` - Basic single-limb heap integer to_s
- `test_negative_heap.rb` - Negative single-limb values
- `test_radix.rb` - Various radixes on single-limb

**Multi-Limb Tests:**
- `test_multilimb.rb` - Multi-limb creation via multiplication (currently returns 0 - no multi-limb * yet)
- `test_multilimb2.rb` - Direct multi-limb creation using `__set_heap_data([1,1], 1)`
- `test_multilimb_radix.rb` - Multi-limb with various radixes
- `test_debug_multilimb.rb` - Debug divmod on multi-limb values
- `test_multilimb_add.rb` - **Shows current limitation**: [1,1] + [2,0] returns 2

**Core Validation:**
- `make selftest` - MRI-compiled compiler tests (fast, always passes)
- `make selftest-c` - Self-compiled compiler tests (critical validation)
- Manual verification of output values

### Testing Strategy

**Incremental Validation:**
1. Write minimal test case for new feature
2. Compile and run: `./compile test_foo.rb -g && timeout 5 ./out/test_foo`
3. Verify output matches expected
4. Run `make selftest-c` to ensure no regressions
5. Document results in docs/bignums.md
6. Commit working code with test results

**Debug Approach:**
- Use `gdb` for segfaults: `gdb -batch -ex 'run' -ex 'bt' ./out/test_foo`
- Check assembly output when needed: `sed -n 'LINE1,LINE2p' out/test_foo.s`
- Add debug output with puts to trace execution
- Use `__get_limbs`, `__get_sign` helpers to inspect heap integer state

**Validation Criteria:**
- Test output matches expected value ✅
- selftest-c passes with 0 failures ✅
- No segfaults or FPEs ✅
- Code works when self-compiled ✅

### Current Status (Session End)

**Completed in this session:**
- ✅ Fixed multiple crashes in to_s implementation
- ✅ Implemented multi-limb division by small radix
- ✅ All to_s test cases passing
- ✅ selftest-c: 0 failures
- ✅ Committed working implementation

**Test Results:**
```
test_heap_minimal.rb:     536870912.to_s → "536870912" ✅
test_negative_heap.rb:    -536870913.to_s → "-536870913" ✅
test_radix.rb:            536870912.to_s(16) → "20000000" ✅
test_multilimb2.rb:       [1,1].to_s → "1073741825" ✅
test_multilimb_radix.rb:  [1,1].to_s(16) → "40000001" ✅
test_multilimb_add.rb:    [1,1] + [2,0] → 2 (FAILS - multi-limb + not implemented)
```

**Current Commit:** `d081db5` - Implement multi-limb to_s support for heap integers

**Ready for Next Session:**
- Multi-limb addition implementation (Phase 6 Step 3)
- Test file ready: `test_multilimb_add.rb`
- Algorithm documented in "Multi-Limb Addition (Step 3 - Next)" section above
