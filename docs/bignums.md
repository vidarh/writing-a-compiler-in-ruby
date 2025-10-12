# Bignum Implementation Plan

## Current Status

**Latest commit:** `5025610` - Add predicates and utility methods to Integer

### What Works
- ✅ **Heap integer arithmetic working!**
- ✅ **selftest-c PASSING with heap integer support!**
- Overflow detection and allocation (lib/core/base.rb:56)
- Integer#__add_heap: heap integer + fixnum (lib/core/integer.rb:89)
- **Test results:**
  - 536870911 + 1 = 536870912(heap) ✅
  - heap + 5 = 536870917 ✅
  - heap + 10 + 20 = 536870942 ✅
- Heap integers work in expressions!
- **Integer#+** migrated from Fixnum#+ (lib/core/integer.rb:57)
- **Integer#__get_raw** extracts values from both fixnums and heap integers (lib/core/integer.rb:45)
- **Integer#__heap_get_raw** handles single-limb heap integer extraction (lib/core/integer.rb:55)
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
- **Integer#inspect** - Proper display of heap integers (lib/core/integer.rb:169)
- **Integer#==** - Equality comparison for both fixnums and heap integers (lib/core/integer.rb:231)
- Integer#__get_raw dispatches based on representation
- **Comparison operators**: >, >=, <, <= (delegate to __get_raw)
- **Arithmetic operators**: %, * (delegate to __get_raw, * checks overflow)
- Integer class documented with dual representation architecture
- `Integer#initialize` sets up @limbs and @sign for heap integers
- `Integer#__set_heap_data` helper for initialization
- `Integer#__init_overflow` helper for heap integer creation

### Progress
- ✅ Phase 1: Integer bignum storage structure (documentation)
- ✅ Phase 2: Detection helpers (stub implementation)
- ✅ Phase 3: Allocation and creation (DONE - but single-limb only)
- ✅ Phase 4: Basic Arithmetic (DONE - but single-limb only, delegates to __get_raw)
- ✅ Phase 5: Operator scaffolding (DONE - all operators exist but use __get_raw)
- ⏳ **Phase 6: Multi-Limb Support (CRITICAL - THE ENTIRE POINT)**
  - [ ] Split values into proper 30-bit limbs in __init_overflow
  - [ ] Multi-limb addition with carry propagation
  - [ ] Multi-limb subtraction with borrow propagation
  - [ ] Multi-limb comparison
  - [ ] Multi-limb to_s conversion
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

**Step 1: Proper limb storage**
- [ ] Fix `__init_overflow` to split 32-bit values into 30-bit limbs
- [ ] Each limb stores 30 bits (unsigned magnitude)
- [ ] limb[0] = bits 0-29, limb[1] = bits 30-59, etc.
- [ ] Sign stored separately in @sign

**Step 2: Multi-limb addition**
- [ ] Implement `__add_multi_limb(other_integer)` for heap + heap
- [ ] Add limb-by-limb with carry propagation
- [ ] Handle different limb counts
- [ ] Return result as new heap integer with proper limb count

**Step 3: Multi-limb subtraction**
- [ ] Implement `__sub_multi_limb(other_integer)` for heap - heap
- [ ] Subtract limb-by-limb with borrow propagation
- [ ] Handle sign changes when result is negative

**Step 4: Multi-limb comparison**
- [ ] Implement `__cmp_multi_limb(other_integer)` returning -1, 0, or 1
- [ ] Compare signs first
- [ ] Compare limb counts for same sign
- [ ] Compare limbs from most significant to least
- [ ] Replace all __get_raw comparisons with this

**Step 5: Multi-limb to_s**
- [ ] Implement proper `to_s` that works on limb array
- [ ] Cannot use __get_raw (only works for 32-bit)
- [ ] Need repeated division by radix across limbs

**Step 6: Update operators**
- [ ] Update Integer#+ to use multi-limb addition
- [ ] Update Integer#- to use multi-limb subtraction
- [ ] Update Integer#==, >, <, etc. to use multi-limb comparison
- [ ] Update Integer#inspect to use multi-limb to_s

**Future (Phase 7-8):**
- [ ] Multi-limb multiplication
- [ ] Multi-limb division

### Phase 9: Automatic Demotion
Optimize by converting small heap integers back to fixnums.

**TODO:**
- [ ] After operations, check if result fits in fixnum
- [ ] Implement `__heap_integer_to_fixnum_if_fits(integer)`
- [ ] Apply in all arithmetic operations

## Technical Constraints

### Tokenizer Limitation
⚠️ **CRITICAL:** `tokens.rb` currently truncates large integer literals because bignum support is incomplete.

**Workaround until Phase 2+ complete:**
- DO NOT use large literals like `1000000000000`
- Instead construct via operations: `1000000 * 1000000`
- Or use shifts: `1 << 40` (but register allocation may be unsafe)

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
