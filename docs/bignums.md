# Bignum Implementation Plan

## Current Status

**Latest commit:** `e5bb93e` - Add Integer#== and implement fixnum + heap integer

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
- ✅ Phase 3.5: Integer#+ infrastructure (DONE)
- ✅ Phase 3.6: Overflow detection (DONE)
- ✅ Phase 3: Allocation and creation (DONE)
- ✅ Phase 4: Basic Arithmetic (DONE - heap + fixnum working!)
- ⏳ Phase 5: Conversions and Comparisons (NEXT - to_i, ==, <, etc.)

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

**Limitations (acceptable for Phase 4):**
- Only single-limb heap integers (values up to 32-bit)
- Subtraction, division, and modulo use __get_raw (extract to fixnum range first)
- No support for true multi-limb arithmetic yet

**TODO for future:**
- [ ] Proper multi-limb arithmetic
- [ ] Optimize operations to avoid unnecessary extractions

### Phase 5: Conversions and Comparisons (PARTIAL)
Make heap integers interoperate properly.

**Completed:**
- ✅ Integer#__get_raw extracts from heap integers (lib/core/integer.rb:45)
- ✅ Integer#>, >=, <, <= comparison operators (lib/core/integer.rb:206-219)
- ✅ Integer#== equality comparison (lib/core/integer.rb:231)
- ✅ Integer#% modulo operator (works via Fixnum with __get_raw)
- ✅ Integer#* multiplication with overflow check (works via Fixnum)
- ✅ Integer#/ division (works via Fixnum with __get_raw)
- ✅ Integer#inspect for proper display (lib/core/integer.rb:169)

**Limitations:**
- Comparisons/operators delegate to __get_raw (extract to fixnum range)
- Won't work correctly for true multi-limb bignums beyond fixnum range
- Temporary solution to enable selftest-c compilation

**TODO:**
- [ ] Implement proper Integer#to_s for heap integers
- [ ] Implement proper multi-limb comparisons
- [ ] Add coercion support
- [ ] Implement remaining operators (**, etc.)

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
