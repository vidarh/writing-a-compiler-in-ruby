# Bignum Implementation Reference

## Current Status

All 9 phases complete. Multi-limb bignum support is fully implemented and working.

- All 9 phases complete (storage, detection, allocation, arithmetic, operators, multi-limb, multiplication, division, demotion)
- Fixnum minimized to 10 critical methods (down from 58)
- `selftest-c` passes with 0 failures
- Heap integers work for values exceeding fixnum range (-2^29 to 2^29-1)
- Automatic overflow detection and promotion to heap integers
- Automatic demotion back to fixnums when results fit

## Architecture and Design Decisions

### Unified Integer Class (No Separate Bignum)

There is no separate Bignum class. The Integer class handles both representations:
- **Small values**: Tagged fixnums (`value << 1 | 1`)
- **Large values**: Heap-allocated Integer objects with `@limbs` instance variable

Integer methods check representation and dispatch accordingly. This matches modern Ruby where Bignum is unified into Integer.

### Fixnum as Minimal Wrapper

Fixnum exists only as a minimal vtable wrapper (10 critical methods, 85 lines). It cannot be fully eliminated because the compiler uses class identity checks on integers during compilation. All non-critical methods are inherited from Integer.

**Critical Fixnum methods**: `class`, `%`, `__get_raw`, `<`, `>`, `<=`, `>=`, `<=>`, `-`, `*`, `/`

### Why Array for Limbs?

Arrays are already implemented and working, simplify memory management (GC handles it), and each limb is a fixnum (tagged), so array operations are safe.

### Sign Handling

Separate `@sign` field simplifies arithmetic. Magnitude stored in `@limbs` as positive values. Operations work on magnitudes, then apply sign. This avoids two's complement complexity across limbs.

### Bootstrap Constraint: No Large Literals During Compilation

The compiler cannot use large literals (> 30-bit) during self-compilation because overflow triggers heap integer allocation. Until multi-limb support was complete, this created a bootstrap problem. Workaround: use computed values (`1 << 28`) instead of large literals.

## Memory Layout

### Tagged Fixnum

```
Value directly in register/memory: (n << 1) | 1
- Lowest bit = 1 marks as fixnum
- Upper 31 bits = 30-bit signed value + sign bit
- Range: -536,870,912 to 536,870,911
```

### Heap-Allocated Integer

```
[vtable ptr]      # 4 bytes - points to Integer class vtable
[@limbs]          # 4 bytes - pointer to Array of fixnum limbs
[@sign]           # 4 bytes - fixnum: 1 or -1
```

### Detection

- `value & 1 == 1` -> tagged fixnum
- `value & 1 == 0` -> heap object (including heap Integer)

### Limb Representation

Each limb is a tagged fixnum (30-bit value). Stored in array from least significant to most significant. Example: 2^40 = limb[0]=0 (low 30 bits), limb[1]=1024 (next 30 bits).

## Phase Summary

### Phase 1: Integer Bignum Storage Structure

Added documentation and infrastructure to Integer class for dual representation architecture. No functional changes.

### Phase 2: Detection Helpers

Added `__is_heap_integer?` method to Integer for checking representation type.

### Phase 3: Allocation and Creation

Implemented `Integer#initialize`, `__set_heap_data`, `__init_overflow` helpers. Migrated `Fixnum#+` to `Integer#+` with representation dispatch. Fixed register clobbering bugs in `sarl`/`sall` instructions.

### Phase 4: Basic Arithmetic

Implemented `Integer#+` and `Integer#-` with all four dispatch cases (fixnum+fixnum, fixnum+heap, heap+fixnum, heap+heap). Added overflow detection. Limited to single-limb (32-bit values) — scaffolding for multi-limb.

### Phase 5: Operator Scaffolding

Added all operator methods to Integer class (comparison, arithmetic, unary, bitwise, predicates, utility). All delegate to `__get_raw` — functional only for 32-bit values.

### Phase 6: Multi-Limb Support

The critical phase enabling true bignum arithmetic:
- **Step 1**: Multi-limb comparison operators via `__cmp` dispatch method
- **Step 2**: Multi-limb `to_s` using repeated division. Implemented `__divmod_by_fixnum` and `div64` s-expression for 64-bit unsigned division
- **Step 3**: Multi-limb addition with carry propagation (`__add_magnitudes`)
- **Step 4**: Multi-limb subtraction with borrow propagation (`__subtract_magnitudes`)
- **Step 5**: Overflow value splitting into proper 30-bit limbs in `__add_with_overflow`

Key bootstrap challenge: cannot use large literals (`>= 2^30`) during self-compilation. Solved by computing `2^30` in s-expression as raw untagged value via `__limb_base_raw`.

### Phase 7: Multi-Limb Multiplication

Added `mulfull` s-expression (widening 64-bit multiply using x86 one-operand `imull`). Implemented school multiplication algorithm:
- `__multiply_limb_by_fixnum_with_carry` — single limb multiply with carry
- `__multiply_heap_by_fixnum` — multi-limb by fixnum
- `__multiply_heap_by_heap` — school multiplication (O(n^2))
- Updated `Integer#*` dispatcher for all type combinations

Known bug: `fixnum * heap` returns garbage (workaround: use `heap * fixnum`).

### Phase 8: Multi-Limb Division (by Fixnum)

Implemented `div64` s-expression for 64-bit unsigned division. Multi-limb division by small fixnum works for `to_s` digit extraction. Heap / heap division not yet implemented.

### Phase 9: Automatic Demotion

Results that fit in fixnum (single limb < 2^29) are automatically demoted back to tagged fixnums in all arithmetic operations.

## Key Methods Reference

### Public API

| Method | Description |
|--------|-------------|
| `Integer#+`, `-`, `*` | Binary arithmetic with multi-limb support |
| `Integer#>`, `>=`, `<`, `<=` | Comparison with multi-limb dispatch |
| `Integer#to_s(radix)` | String conversion for any radix (2-36) |
| `Integer#==`, `!=` | Equality comparison |
| `Integer#-@`, `+@` | Unary operators |

### Internal Methods

| Method | Description |
|--------|-------------|
| `__is_heap_integer?` | Check if value is heap-allocated |
| `__set_heap_data(limbs, sign)` | Set limbs and sign on heap integer |
| `__get_raw` | Extract raw value (single-limb only) |
| `__cmp(other)` | Central comparison dispatch |
| `__add_magnitudes` | Multi-limb addition with carry |
| `__subtract_magnitudes` | Multi-limb subtraction with borrow |
| `__multiply_limb_by_fixnum_with_carry` | Widening limb multiply |
| `__multiply_heap_by_fixnum` | Multi-limb by fixnum multiply |
| `__multiply_heap_by_heap` | School multiplication |
| `__divmod_by_fixnum(radix)` | Division by small fixnum |
| `__limb_base_raw` | Compute 2^30 in s-expression |
| `__is_negative`, `__negate` | Sign operations via @sign |
| `__less_than`, `__greater_than` | Helpers avoiding operator recursion |

## Known Limitations and Future Work

### Compiler-Level Limitations

1. **Fixnum class cannot be fully eliminated** — compiler uses class identity checks on integers. Minimized to 10 methods.
2. **Fixnum-as-receiver dispatcher bug** — `fixnum + heap` and `fixnum * heap` return garbage. Workaround: use `heap + fixnum` or `heap * fixnum`.

### Arithmetic Limitations

**Working operators**: `+`, `-`, `*`, `>`, `>=`, `<`, `<=` (multi-limb)

**Broken operators** (use `__get_raw`, single-limb only):
- Comparison: `<=>`, `==`
- Arithmetic: `/`, `-@`, `%`, `pred`
- Bitwise: `&`, `|`, `^`, `<<`, `>>`
- Other: `abs`, `zero?`, `inspect`, `chr`

### Future Enhancements

- Fix fixnum-as-receiver dispatcher (requires compiler changes)
- Implement multi-limb `<=>` and `==`
- Implement multi-limb division (heap / heap)
- Implement multi-limb bitwise operations
- Karatsuba multiplication for large numbers (optimization)
- Consider making Fixnum an alias for Integer (requires compiler changes)

## References

- `lib/core/base.rb:56` — `__add_with_overflow` function
- `lib/core/integer.rb` — Integer class (handles both fixnum and heap integers)
- `lib/core/fixnum.rb` — Fixnum class (10 critical methods, 85 lines)
- `compile_arithmetic.rb` — `compile_mulfull` and `compile_div64`
- `docs/DEBUGGING_GUIDE.md` — Debugging patterns
