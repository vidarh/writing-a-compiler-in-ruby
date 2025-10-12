# Bignum Implementation Plan

## Current Status

**Latest commit:** `dc2e2e9` - Add heap integer arithmetic dispatch in Integer#+

### What Works
- Overflow detection in `__add_with_overflow` helper (lib/core/base.rb:56)
- Detects when addition result doesn't fit in 30-bit signed integer
- Currently prints "OVERFLOW" and returns wrapped value
- **Integer#+** migrated from Fixnum#+ (lib/core/integer.rb:34)
- **Tag bit checking** via bitand in s-expression context
- Integer#+ dispatches based on representation:
  - Tagged fixnum → uses __add_with_overflow
  - Heap integer → calls __add_heap (stub)
- Integer class documented with dual representation architecture
- `Integer#initialize` sets up @limbs and @sign for heap integers
- `Integer#__set_heap_data` helper for initialization
- selftest-c: ✅ PASSING

### Progress
- ✅ Phase 1: Integer bignum storage structure (documentation)
- ✅ Phase 2: Detection helpers (stub implementation)
- ✅ Phase 3.5: Integer#+ infrastructure (DONE)
- ⏳ Phase 3: Allocation and creation (READY TO IMPLEMENT)

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

### Phase 3: Allocation and Creation (READY TO IMPLEMENT)
Replace overflow detection with actual bignum allocation.

**Completed:**
- ✅ Created `Integer#initialize` to set up @limbs/@sign (lib/core/integer.rb:21)
- ✅ Created `Integer#__set_heap_data(limbs, sign)` helper (lib/core/integer.rb:28)
- ✅ Verified `(callm Integer new)` allocates successfully
- ✅ Identified blocker requirement: Integer#+ infrastructure
- ✅ Implemented Integer#+ with representation dispatch (Phase 3.5)
- ✅ Tag bit checking works in s-expression context

**Blocker Resolved:**
The blocker (need Integer#+ before allocation) has been resolved in Phase 3.5.

**Next Steps:**
1. Implement simple heap integer creation from overflow value
2. Store value in @limbs array (initially single limb)
3. Set @sign based on result sign
4. Return heap integer from __add_with_overflow
5. Test that it gets properly dispatched to __add_heap

**Investigation Notes:**
- bitand in nested s-expression context causes segfault (register allocation bug)
- bitand works fine when used directly in single s-expression
- Solution: do tag checks entirely within s-expressions, not via Ruby methods
- Proc allocation pattern: allocate, call setter method, return object

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

### Phase 4: Basic Arithmetic
Implement arithmetic operations on heap integers.

**TODO:**
- [ ] Update Integer#+ to handle heap integer + fixnum
- [ ] Update Integer#+ to handle heap integer + heap integer
- [ ] Automatic promotion in overflow cases
- [ ] Update Integer#- (subtraction)
- [ ] Update Integer#* (multiplication)
- [ ] Update Integer#/ (division)

### Phase 5: Conversions and Comparisons
Make heap integers interoperate properly.

**TODO:**
- [ ] Update Integer#to_s to handle heap representation
- [ ] Update Integer#== to handle heap representation
- [ ] Update Integer#< to handle heap representation
- [ ] Update Integer#> to handle heap representation
- [ ] Add coercion support

### Phase 6: Automatic Demotion
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
