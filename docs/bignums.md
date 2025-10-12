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
- ⏳ **Phase 6: Multi-Limb Support (IN PROGRESS)**
  - [ ] Split values into proper 30-bit limbs in __init_overflow (Step 5 - TODO)
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
- Phase 7: Multi-Limb Multiplication (future)
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
