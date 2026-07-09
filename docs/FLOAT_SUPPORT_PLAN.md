# Float support — status

Real IEEE-754 `Float` in the self-hosting compiler. The implementation plan that this file
used to hold (Phases 1–3: literal self-hosting, x87 arithmetic/comparison/conversion codegen,
`to_s`/`Math`/`Float()`, IEEE corners) is **essentially complete** — see git history for the
phase-by-phase record. This file now tracks the CURRENT STATE and the remaining tails.

## Current state (2026-07-09, sweep @ 1c52600)

Full `rubyspec/language rubyspec/core` sweep (2158 files): **PASS 545, CRASH 7, TIMEOUT 8.**
Numeric-family categories:

| category | files | PASS | % |
|---|---|---|---|
| core/float   | 50 | 47 | **94%** |
| core/complex | 43 | 39 | **91%** |
| core/math    | 27 | 25 | **93%** |
| core/rational| 32 | 22 | 69% |
| core/integer | 67 | 39 | 58% |
| core/numeric | 46 | 19 | 41% |

Real Float values flow end-to-end self-hosted: arithmetic, Int↔Float conversion, ordered
comparison (with NaN unorderedness), unary ops, predicates, `to_s`/`inspect` (shortest
round-trip), `Kernel#Float()`, `String#to_f`, the full `Math` module, and real
`INFINITY/NAN/MAX/MIN/EPSILON`. Float itself is done.

## Remaining tails (open)

Float / Complex / Math (the last few percent):
- **`core/float/comparison_spec` (1 fail):** a `do`-block `<=>` codegen bug (not a Float bug).
- **`core/float/round_spec` (1 fail):** the final rounding digit needs the bignum heap*heap
  multiply, which is broken ≥8 limbs — see [[compiler_bignum_heap_multiply_bug]].
- **`core/float/float_spec` (2 fails):** a `Float.new` literal-parsing refactor.
- **`core/complex/{to_s,to_r}` (1 each):** blocked by the should_receive-on-existing-method mock
  limitation; `inspect` (2) and `marshal_dump` (1) are value tails.
- **`core/math/{atanh,log2}` (1 each):** last-ULP precision.
- **`sprintf`/`String#%` `%e %g %E %G`** still route through the pure-Ruby fixed-decimal
  `__format_float` and are wrong; needs a C `__snprintf_float(obj, buf, conv, prec)` helper
  (tgc.o rebuild via the `ruby-compiler-buildenv` docker image). Affects `kernel/sprintf` +
  `string/modulo` float examples.

**`core/numeric` (41%) is the deceptive low number.** Its FAILs (abs, angle, arg, coerce,
comparison, div, magnitude, modulo, phase, polar, rect, remainder, nonzero, …) are NOT missing
numeric functionality — they build a `NumericSpecs::Subclass` and `should_receive` its
`==`/`coerce`/`<=>`/`to_i`, which our mock framework cannot override (see
[[compiler_stub_override_blocks_specs]]). Implementing more numeric methods will NOT flip them.

`core/rational` and `core/integer` tails are mostly the bignum heap-multiply bug (gcd/lcm/ceildiv,
`10**n` for large n) plus coerce mocks.

## Remaining Float-specific work (in priority order)

1. **Bignum heap*heap multiply** (≥8 limbs → wrong digits) — the last blocker for `float/round`
   (final digit) plus `rational/to_f`, `integer/gcd`+`lcm`+`ceildiv`, `10**n` for n≳64. Root is carry
   propagation in `__multiply_heap_by_heap`; see the bignum-heap-multiply memory.
2. **`sprintf`/`String#%` `%e/%g/%E/%G`** — route to a C `__snprintf_float(obj, buf, conv, prec)`
   helper (tgc.o rebuild via the `ruby-compiler-buildenv` docker image); today they use the pure-Ruby
   fixed-decimal `__format_float` and are wrong. Bounded, mechanical.
3. **do-block `<=>` codegen** (`float/comparison_spec`) and **`Float.new` literal parse**
   (`float/float_spec`) — two deep codegen tails.

The big cross-cutting blocker for the numeric FAMILY (numeric/complex mocks) is the
`define_method`→vtable stub-override capability — that is a WHOLE-COMPILER target, not Float-specific.

**For the compiler-wide "what to do next" (performance + the highest-leverage feature), see
[`NEXT_STEPS.md`](NEXT_STEPS.md).** The short version: the binding constraint is now **compile speed**
(lib/core is recompiled on every spec); the keystone feature is **dynamic-ivar reflection**, which
unblocks the COREMARSHAL ~40% compile-speedup, Marshal specs, and the define_method→vtable
stub-override at once.
