# Fixnum to Integer Migration Plan

## Current Status (Commit 59b807e)

**Working state:** ✅ `make selftest-c` passes with 0 failures

### Current Architecture

- **Tagged fixnums:** Loaded via `:Fixnum` class in `compile_calls.rb:249`
- **Heap integers:** Allocated as `Integer` objects with `@limbs` and `@sign`
- **Method dispatch:** All integer methods are in `Integer` class
- **The problem:** When fixnum is the receiver (e.g., `3 + heap_int`), compiler loads `:Fixnum` class, but methods are in `:Integer` class

### What Works

- ✅ All bignum features (multi-limb addition, subtraction, multiplication, division)
- ✅ Heap integer operations (heap + fixnum, heap * fixnum, heap + heap, heap * heap)
- ✅ Mixed operations where heap is receiver work correctly
- ✅ Overflow detection and automatic promotion to heap integers
- ✅ Automatic demotion from heap to fixnum when results fit

### Known Limitations

1. **Fixnum as receiver fails for heap operations:**
   - `fixnum + heap` → Works (delegates to heap)
   - `fixnum * heap` → Returns garbage (method not in Fixnum vtable)
   - Workaround: Use `heap * fixnum` instead

2. **Comparison operators broken for heap integers:**
   - `__cmp` dispatch fails silently
   - Workaround: Use `__is_negative` for sign checks

## Previous Failed Migration Attempts

18 commits after 59b807e attempted to migrate from Fixnum to Integer:

### What was tried (commits c5ad0e3 through ba00ac8):

1. **Created `integer_base.rb`** - Minimal fixnum-only Integer class (no Array dependency)
2. **Modified `lib/core/core.rb`** - Load `integer_base.rb` before Array, full `integer.rb` after
3. **Moved `__int` function** - From fixnum.rb to integer.rb
4. **Migrated methods** - Moved all Fixnum methods to Integer class
5. **Changed `compile_calls.rb:249`** - From `:Fixnum` to `:Integer`
6. **Attempted fixes** - Multiple commits trying to fix resulting crashes

### Why it failed:

**Root cause:** Changing `compile_calls.rb:249` to `:Integer` causes immediate crashes:
- Even `puts 42` segfaults
- Hash#[]= crashes with null pointer dereference (0x00000000)
- Assembly shows `__vtable_missing_thunk_Integer`
- Integer class vtable is not properly initialized or referenced

**Deeper issue:** The compiler's class initialization and vtable system assumes:
- Tagged values (bit 0 = 1) map to Fixnum class
- When changed to Integer, the vtable lookup mechanism breaks
- This is a fundamental compiler limitation, not just a missing method issue

## Migration Strategy

### Phase 1: Preparation (No Fixnum→Integer switch yet)

**Goal:** Set up Integer class infrastructure without changing `compile_calls.rb:249`

Steps:
1. ✅ Create `integer_base.rb` with minimal fixnum-only methods
2. ✅ Ensure `integer_base.rb` has NO Array dependency
3. ✅ Move `__int` from fixnum.rb to integer_base.rb
4. ✅ Update `lib/core/core.rb` load order:
   - Load `integer_base.rb` before Array (early bootstrap)
   - Load full `integer.rb` after Array (bignum support)
5. ✅ Keep `compile_calls.rb:249` as `:Fixnum` during this phase
6. ✅ Test: `make selftest-c` should still pass

### Phase 2: Method Migration (Still using :Fixnum)

**Goal:** Ensure all integer methods exist in both Fixnum and Integer classes

Steps:
1. ✅ Keep critical methods in Fixnum class (for compatibility)
2. ✅ Duplicate methods in Integer class (for heap integers)
3. ✅ Test each batch of method migrations
4. ✅ Keep `compile_calls.rb:249` as `:Fixnum`
5. ✅ Test: `make selftest-c` should still pass

### Phase 3: Investigate Vtable Issue

**Goal:** Understand why changing to `:Integer` breaks vtable lookup

Before attempting the switch, investigate:
1. How is Fixnum class vtable created?
2. How does `load_class` interact with vtables?
3. What happens when Integer is loaded for tagged values?
4. Can we pre-populate Integer vtable with all needed methods?

**Research areas:**
- `compile_class.rb` - Class compilation and vtable generation
- `compile_calls.rb:load_class` - How tagged values get their class
- Runtime class initialization order
- Vtable population mechanism

### Phase 4: The Switch (High Risk)

**Only after Phase 3 investigation is complete:**

1. Change `compile_calls.rb:249` from `:Fixnum` to `:Integer`
2. Test with minimal program: `puts 42`
3. If it crashes, debug with GDB to understand vtable state
4. If successful, test `make selftest-c`

### Phase 5: Cleanup

If Phase 4 succeeds:
1. Remove Fixnum class entirely
2. Update documentation
3. Test all functionality

## Patch Analysis

The patch from 59b807e..ba00ac8 contains:

### Core Changes:
- `lib/core/integer_base.rb` (143 lines) - NEW FILE
- `lib/core/integer.rb` (+613 lines) - Major expansion
- `lib/core/core.rb` - Load order changes
- `lib/core/fixnum.rb` - Removal of `__int`
- `compile_calls.rb:249` - `:Fixnum` → `:Integer` (THE BREAKING CHANGE)

### Supporting Changes:
- `lib/core/array.rb` - Handle both fixnum and heap in `__copy_init`, `__offset_to_pos`, `[]=`
- `lib/core/hash.rb` - Hash function changes
- `lib/core/string.rb` - `is_a?(Fixnum)` → `is_a?(Integer)`
- `lib/core/symbol.rb` - Lazy initialization of `@@symbols`
- `compile_arithmetic.rb` - `compile_div` register allocation fix
- `lib/core/base.rb` - Double parentheses fix

## Current Progress

### Phase 1: ✅ COMPLETE (Commit 708a053)
- ✅ Created `integer_base.rb` with minimal fixnum-only methods
- ✅ NO Array dependency - safe for early bootstrap
- ✅ Moved `__int` function from fixnum.rb to integer_base.rb
- ✅ Updated `lib/core/core.rb` load order
- ✅ `make selftest-c`: 0 failures

### Phase 2: 🔄 IN PROGRESS
- ✅ Added Integer#class (Commit 2505685)
- ✅ Added Integer#hash (Commit 2505685)
- ✅ Added Integer#div (Commit 537631b)
- ✅ Added Integer#divmod (Commit 537631b)
- ⏸️ Remaining methods to add: 23 methods from Fixnum still need migration

**Methods still needed:**
- chr, ord, mul, **, magnitude, times, frozen?, ceil, floor, truncate
- [], allbits?, anybits?, nobits?, bit_length, size, to_int, to_f
- gcd, lcm, gcdlcm, ceildiv, digits, coerce, !

**Blocker found:** Adding chr, ord, and mul together caused segfault at runtime.
- Need to add remaining methods one at a time
- Test after each addition
- Some methods may need modification for heap integer compatibility

## Next Steps

1. ✅ Created migration plan document
2. ✅ Completed Phase 1: integer_base.rb creation
3. 🔄 Continue Phase 2: Add remaining methods from Fixnum one at a time
4. Test after EACH method addition
5. Commit when batch passes `make selftest-c`
6. After Phase 2 complete: Investigate vtable issue (Phase 3)
7. DO NOT change `compile_calls.rb:249` until Phase 3 investigation is complete

## Critical Rules

1. **Test after every change:** `make selftest-c` must pass before committing
2. **Small steps:** One logical change per commit
3. **No :Integer switch:** Keep `:Fixnum` until vtable issue is understood
4. **Document failures:** If something breaks, document why before reverting
5. **Bootstrap safety:** integer_base.rb must have ZERO Array dependency
