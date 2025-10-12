# Bignum Implementation Plan

## Current Status

**Latest commit:** `4772ae8` - Add minimal overflow detection to Fixnum#+

### What Works
- Overflow detection in `__add_with_overflow` helper (lib/core/base.rb:56)
- Detects when addition result doesn't fit in 30-bit signed integer
- Currently prints "OVERFLOW" and returns wrapped value
- selftest-c: ✅ PASSING

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

### Phase 1: Integer Bignum Storage Structure (IN PROGRESS)
Extend Integer class to support heap-allocated bignum representation.

**TODO:**
- [ ] Add @limbs and @sign to Integer class
- [ ] Methods must check: "Am I a tagged fixnum or heap object?"
- [ ] Tagged fixnums continue to work as before
- [ ] Heap-allocated Integers use @limbs/@sign

**Design Decision:**
- Integer unifies both fixnum and bignum representations
- Fixnum class may become obsolete or just a compatibility layer
- Most integer support is currently in Fixnum (legacy) - may need migration

### Phase 2: Detection Helpers (NEXT)
Add methods to detect whether an Integer is tagged or heap-allocated.

**TODO:**
- [ ] Add `__is_heap_integer?` method to detect heap-allocated integers
  - Check if @limbs is set (non-nil)
  - Tagged fixnums won't have instance variables
- [ ] Add helper to check representation at s-expression level
  - Low-level check: test bit 0 of value

### Phase 3: Allocation and Creation
Replace overflow detection with actual bignum allocation.

**TODO:**
- [ ] Implement `__alloc_heap_integer(limb_count)` in lib/core/base.rb
  - Allocate Integer object with space for instance variables
  - Set up @limbs array
  - Set up @sign field
- [ ] Implement `__fixnum_to_heap_integer(value)` helper
  - Takes a 30-bit fixnum value
  - Creates single-limb heap integer
  - Handles sign appropriately
- [ ] Update `__add_with_overflow` to call heap allocation on overflow
  - Instead of printing "OVERFLOW", create heap integer object
  - Store result in limbs

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
