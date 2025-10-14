# Fixnum#class Investigation

## Summary

Investigation into why changing `compile_calls.rb:249` from `:Fixnum` to `:Integer` causes crashes.

## Methodology

Systematically removed methods from Fixnum class one at a time to identify critical methods that cannot be inherited from Integer.

## Results

### Methods that CAN be removed from Fixnum (Integer version works):

✅ **`__get_raw`** - Integer's version checks tagged vs heap, works perfectly
- Fixnum version: `%s(sar self)` - direct shift
- Integer version: Checks if tagged, then uses `(sar self)` or calls `__heap_get_raw`
- **Result:** Integer version is COMPATIBLE with fixnums

✅ **`hash`** - Integer's version works
- Both return `self` anyway
- **Result:** No difference in behavior

✅ **`inspect`** - Can be removed
✅ **`chr`** - Can be removed

### Methods that CANNOT be removed from Fixnum:

❌ **`class`** - **CRITICAL FAILURE**
- Fixnum version: Returns `Fixnum`
- Integer version: Returns `Integer`
- **Result:** Removing Fixnum#class causes **COMPILATION SEGFAULT**
  - Crash occurs at ~68000 __cnt during self-compilation
  - The compiler itself crashes when compiling test/selftest.rb
  - This is NOT a runtime crash - it's a compile-time crash

## Critical Finding

**The compiler uses `.class` on integer values during compilation!**

When `Fixnum#class` is removed:
1. Fixnums inherit `Integer#class`
2. Calling `.class` on a fixnum returns `Integer` instead of `Fixnum`
3. The compiler crashes with segfault during compilation

This suggests:
- The compiler has code that calls `.class` on integers
- The compiler expects tagged integers to have class `Fixnum`
- When `.class` returns `Integer` instead, something breaks

## Hypothesis

When we change `compile_calls.rb:249` to load `:Integer` for tagged values:
1. Tagged integers get Integer as their class
2. `fixnum.class` returns `Integer` instead of `Fixnum`
3. Some compiler code checks `obj.class == Fixnum` or similar
4. This check fails, causing incorrect behavior
5. Eventually leads to null pointer dereference or segfault

## Next Steps

1. **Find where the compiler uses `.class` on integers during compilation**
   - Search for `class ==`, `is_a?(Fixnum)`, etc. in compiler code
   - Add debug output to trace when integers have `.class` called during compilation

2. **Understand the class identity check**
   - Why does the compiler need to distinguish Fixnum from Integer?
   - Can this check be made more flexible?

3. **Potential solutions:**
   - Make Fixnum an alias for Integer instead of a subclass?
   - Change compiler code to check for `Integer` instead of `Fixnum`?
   - Keep Fixnum as a thin wrapper that only defines `class`?

## Test Command

```bash
# Remove Fixnum#class and test:
# Edit lib/core/fixnum.rb, comment out class method
make selftest-c
# Result: Segfault at ~68000 __cnt during compilation
```

## Complete Critical Methods Investigation

**Comprehensive testing by removing methods systematically identified the EXACT set of critical methods:**

### Critical Fixnum Methods (Cannot be removed):

1. **`class`** - Returns `Fixnum` (compiler needs this for class identity)
2. **`%`** - Modulo operator (used during compilation)
3. **`__get_raw`** - Extracts raw integer value from tagged fixnum
4. **`<`, `>`, `<=`, `>=`, `<=>`** - All comparison operators
5. **`-`** - Subtraction
6. **`*`** - Multiplication
7. **`/`** - Division

### Non-Critical Fixnum Methods (Can be safely removed):

✅ All other methods can be removed and inherited from Integer:
- `__get_raw`, `hash`, `inspect`, `chr` (tested individually - work)
- `to_s`, `to_i`, `zero?`, `ceil`, `floor`, `[]`
- `!=`, `!`
- `div`, `divmod`, `mul`
- `**` (power)
- `&`, `|`, `^` (bitwise AND, OR, XOR)
- `~`, `<<`, `>>` (bitwise NOT, left shift, right shift)
- `-@`, `+@` (unary minus/plus)
- `abs`, `magnitude`, `ord`, `times`
- `pred`, `succ`, `next`, `frozen?`, `even?`, `odd?`
- `allbits?`, `anybits?`, `nobits?`, `bit_length`, `size`
- `to_int`, `to_f`, `truncate`
- `gcd`, `lcm`, `gcdlcm`, `ceildiv`, `digits`, `coerce`

**Total:** Only 10 methods need to be in Fixnum (class + % + __get_raw + 5 comparisons + 3 arithmetic ops). All other 48+ methods can be inherited from Integer!

## Conclusion

The migration is blocked by compiler code that relies on fixnums having:
1. Class identity `Fixnum` (via `.class` method)
2. Specific implementations of core arithmetic and comparison operators

Simply changing the vtable lookup won't work until we fix the compiler's assumptions about integer class identity and ensure all critical methods are available.
