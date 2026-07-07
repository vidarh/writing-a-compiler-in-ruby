# Float support — prioritised implementation plan

## Full-sweep regression triage (2026-07-07, after Phase 1 + Phase 2 items 6/9)

A full local `rubyspec/language rubyspec/core` sweep (2158 files) vs the committed
baseline: **PASS 376→394 (+18)**, FAIL 1752→1732, **CRASH 22→23 (+1)**, TIMEOUT 7→8 (+1).
The +18 PASS is the Float payoff (Complex/Rational/Hash/Range/Float specs). The regressions
are a **known second-order effect**: a STUBBED Float method that returned a constant
(`Float#>=`→false, `Float#==`→false, `Float#<=`) masked latent bugs in *non-float* code;
making Float real flips those code paths and exposes the bug. Verified each in isolation
(setarch -R) and at the pre-Float baseline (all merely FAILed there, no crash) — so they
are genuine, my-change-exposed, not sweep flakes. (`integer/even` TIMEOUT was a 16-way-load flake — passes in isolation. `array/sample` is NOT a flake:
it is a genuinely slow statistical fairness test — `measure_sample_fairness_large_sample_size(100,80,
4000)` does ~320k sample ops — that exceeds the 20s spec timeout under the ~100x-slower self-hosted
runtime. Not a code bug; can't be fixed short of a much faster runtime.)

- **FIXED (commit a51bb36):** `array/repeated_permutation` FAIL→CRASH — `repeated_permutation(3.7)`
  never truncated the count, so the `length == n` base case never held → infinite recursion.
  Fix: `n = n.to_int unless Integer`. Restores CRASH to baseline **22**.
- **TODO (harness-layout crash, count-neutral):** `module/autoload` FAIL→CRASH — crashes inside
  the harness `it` running an example (same layout/harness class as the `float/to_s`,`float/inspect`
  spec-file crashes). Offset in the count by `language/alias_spec` improving CRASH→FAIL.
- **`Integer#<=(Float)` returned false** (should coerce) — FIXED (commit 69544ef), plus the
  `bsearch` hang that fix exposed (commit ca95425).
- **ROOT CAUSE of the `2.1e-314` garbage (FIXED, commit 7f0bcdb):** `Integer#+ - * / % remainder div`
  returned a bare `Float.new` for Float operands, and `Float.new`'s stub initialize leaves the raw
  double = `0x0000000100000001` = `2.1219957915e-314`. Every `int <op> float` produced that denormal
  (seen across numeric/step and array/sample's chi-squared). Fixed by coercing (`self.to_f <op>
  other`); also added `Float#% remainder ** ` (** = exponentiation by squaring). +13 sweep improvements.
- **BLOCKED (timeout):** `numeric/step` FAIL→TIMEOUT. `Integer#step`'s keyword forms (`step(to:, by:)`)
  still misbehave. The proper fix (keyword support in `Integer#step`) is BLOCKED by a
  compiler bug: **keyword args are misrouted into an optional positional param** — `def g(a = nil,
  to: nil); g(to: 5)` yields `[{:to=>5}, nil]` instead of `[nil, 5]` (the kwargs Hash is grabbed by
  `a`). Keyword params work ONLY when every positional before them is REQUIRED. See
  [[compiler_kwargs_misrouted_to_optional_positional]]. Fixing that compiler bug (in
  rewrite_keyword_args / rewrite_default_args) would unblock this and likely many other keyword specs,
  but it is a hot compiler path — a dedicated, carefully-gated task.
- **Found (not float, pre-existing):** string LITERALS with an embedded `\x00` truncate at the NUL
  (`"abc\x00def".length` -> 3, not 7; a leading `\x00` -> length 0). Real binary data (e.g. from
  `Array#pack`) is binary-safe and fine; only `\x00`-bearing *literals* are affected. Blocks the
  unpack-from-literal `array/pack`+`string/unpack` float examples even though pack/unpack round-trips
  work. Likely the literal is stored as a C string truncated at NUL.
- **TODO (PASS→FAIL, not crashes):** `enumerator/lazy/filter_map`, `struct/eql` — uninvestigated.

**Do NOT update the tracked `docs/spec_status.md` until these are resolved and a CLEAN full
re-sweep runs** (the current sweep shows CRASH 23 — committing it would record a regression).
Lesson captured in memory: [[compiler_stub_masks_latent_bugs]].

---

**Goal:** real IEEE-754 `Float` in the self-hosting compiler. Unblocks ~2,300+
assertions (float, math, complex, rational, kernel/Float, numeric/step, pack/unpack
float dirs, sprintf) and turns 4 stub-driven CRASH files (`float/divide`,
`float/inspect`, `float/to_s`, `integer/fdiv`) into passing/failing — so it *lowers*
the crash count rather than risking it.

## What already exists (do NOT rebuild)

- **Object layout:** a `Float` is `[vtable_ptr @ slot0][raw 8-byte double @ offset 4]`
  (`lib/core/float.rb` reserves the 8 bytes via `@value_low`/`@value_high`; the value
  is stored raw, not as two tagged ints).
- **Literal emission (MRI-hosted only):** `compiler.rb:161` catches an `is_a?(Float)`
  token, registers a `.float_N` label in `@float_constants`, emits `Float.new`, then
  `@e.storedouble(:eax, 4, label)`. `output_constants` (compiler.rb:234) emits
  `.double <value>` in rodata; `storedouble` (emitter.rb:309) does `fldl label` /
  `fstpl 4(base)` — i.e. x87 already loads/stores doubles.
- **Tokeniser** already recognises float + scientific-notation literals
  (`tokens.rb` `Number.expect`, ~line 225) — but it finishes with `num.to_f`
  (a Ruby Float via the compiler's *own* `String#to_f`).

## The two real blockers

1. **Literals are MRI-only.** `num.to_f` uses the compiler's stubbed `String#to_f`
   when self-compiled, so every float literal becomes `0.0` under selftest-c
   (decimal→IEEE would itself need working Float — a chicken-and-egg). Fix: keep the
   literal's **decimal string** end-to-end and emit `.double "<string>"` — `gas`
   does decimal→IEEE at assemble time, needing no compile-time float math. Works
   identically MRI-hosted and self-hosted.
2. **No float codegen beyond load/store.** `emitter.rb` has `fldl`/`fstpl` only —
   no `fadd/fsub/fmul/fdiv`, no int↔double, no compare. These must be added.

## Representation & gating (applies throughout)

- Keep the layout: raw `double` at offset 4. Every Float value (literal or computed)
  is its own heap object; Floats are immutable so results allocate fresh (`Float.new`
  + `fstpl`). A helper `__float_from_st0` (allocate + `fstpl 4(%eax)`) will be reused
  everywhere.
- x87 is stack-based (st0..st7). Discipline: load operands with `fldl`, operate, and
  `fstpl` the single result — never leave values on the FPU stack across a call.
- **Every step gates hard:** `make selftest` + `make selftest-c` both Fails:0 AND
  `tools/crash_battery.sh` clean before committing. Float codegen is *additive*
  (new instructions + a new class's methods, no hot-path rewrite), so its layout-risk
  is far lower than the block-ABI / proc work — but it touches the emitter, so treat
  each emitter change as compiler-critical. Add a `test/repros/battery/` guard per
  landed capability. Re-sweep `float/` + `core/numeric/` after each phase.

---

## Phase 1 — Basics: get real Float VALUES flowing

The bar for "done": `1.5 + 2.5 == 4.0`, `10.0 / 4 == 2.5`, `(3.14 <=> 3.15) == -1`,
`5.to_f == 5.0`, `7.5.to_i == 7` all correct, self-hosted.

1. **Float-literal self-hosting** (compiler + tokeniser). Carry the literal as its
   decimal string: tokeniser returns `[:float, "1.5"]` instead of `num.to_f`; the
   compiler stores the string in `@float_constants`; `output_constants` emits
   `.double "1.5"` verbatim. Delete the `String#to_f` dependency from the literal
   path. Verify: a program full of literals compiles to the *right* bytes under
   selftest-c (compare `p 1.5` MRI vs compiled). Also give `Float::INFINITY`/`NAN`/
   `MAX`/`MIN`/`EPSILON` real `.double` values (`inf`, `nan`, etc. — gas understands
   them) and drop the integer stubs.
   **[DONE — commit 65c9c11]** Literal self-hosting landed; `.double <string>` emitted
   verbatim, `String#to_f` dropped from the literal path. (INFINITY/NAN/MAX/MIN/EPSILON
   real-`.double` values are still integer/empty stubs — folded into Phase-1 item 5.)
2. **Arithmetic codegen** (emitter). Add `faddl/fsubl/fmull/fdivl` (memory-operand
   forms) and the `fld st(i)`/`fxch` helpers needed. Implement `Float#+ - * /` in
   `lib/core/float.rb` via `%s`: `fldl 4(self)`, `fldl 4(other)`, `faddl`, then
   `__float_from_st0`. Mixed operands: if `other` is an Integer/Rational, coerce it to
   Float first (needs step 3's `Integer#to_f`). Handle the divide-by-zero → `Infinity`
   / `0.0/0.0` → `NaN` IEEE behaviour (x87 gives these for free).
   **[DONE — this commit]** `fadd/fsub/fmul/fdiv` primitives (three Float-ptr args,
   `fldl a; f<op>l 4(b); fstpl 4(r)`); `Float#+ - * /` allocate a fresh result and
   coerce non-Float operands via `other.to_f`. Divide-by-zero → Infinity / `0.0/0.0`
   → NaN come free from x87. (`**` still a stub — Phase 2.) Reverse coercion
   (`Integer#+ Float` → `coerce`) not yet wired — left-operand-Float works today.
3. **Int↔Float conversion** (emitter + lib). `Integer#to_f`: `fild` a fixnum, `fstpl`
   (replaces the current stub). `Float#to_i`/`to_int`: truncate toward zero — set the
   FPU rounding mode (or `fisttp` if SSE3 assumed) and `fistpl`. `Float#coerce`.
   (Bignum→double is deferred to Phase 3.)
   **[DONE — this commit]** `fint` primitive (`Integer#to_f` via `fildl`) and `ftoi`
   primitive (`Float#to_i`/`to_int`, x87 RC=truncate around `fistpl` → truncates
   toward zero, verified for negatives). `Float#coerce` not yet added.
4. **Comparison** (emitter + lib). Add `fucompp` + `fnstsw %ax` + `sahf`; implement
   `Float#<=> == < <= > >= eql?` returning proper `-1/0/1`/bool, incl. `NaN`
   unorderedness (`NaN <=> x` is nil; `NaN == NaN` is false). Wire `Comparable`.
   **[DONE — this commit]** `flt`/`fgt`/`feq` primitives (`fucompp; fnstsw %ax; sahf`
   then `setb/seta/sete` with a `setnp` mask so NaN is unordered → all-false).
   `== eql? < <= >= > <=>` implemented; NaN and Integer-coercion verified vs MRI.
   NOTE: `-1/0/1` in `<=>` MUST be `(__int n)` — a bare int in `%s()` is a raw
   machine word (raw 0 is a null pointer → crash). `Comparable` mixin not yet wired.
5. **Basic unary/predicates:** `-@`, `abs`, `zero?`, `nan?`, `infinite?`, `finite?`,
   `hash` (over the 8 raw bytes). Cheap, all reuse st0 load/store.
   **[DONE — this commit]** `fneg`/`fabs` primitives; `-@ +@ abs magnitude zero? nan?
   infinite? finite? hash`. Real constants: `MAX/MIN/EPSILON` as finite literals;
   `INFINITY = 1.0/0.0`, `NAN = 0.0/0.0` COMPUTED at the class-body bottom (gas rejects
   an overflowing/NaN literal). Two pre-existing front-end limits found & worked around
   (NOT Float regressions, both non-crashing):
     - a bare-exponent literal `1e400`/`1e300` mis-tokenises to `0.0` (needs a dotted
       mantissa) — irrelevant once INFINITY is computed;
     - unary minus on a value (`-x`, `-INFINITY`) does not dispatch to `Float#-@`, so
       `infinite?` uses `0.0 - INFINITY` for -Inf. `x.-@` works.

**Phase 1 is COMPLETE.** Real Float values flow end-to-end self-hosted: arithmetic,
Int↔Float conversion, ordered comparison (+NaN), unary ops, predicates, real
INFINITY/NAN/MAX/MIN/EPSILON. Gates held every commit (selftest / selftest-c Fails:0,
crash battery clean — now 107 guards incl. float_arith/float_compare/float_unary/
float_var_closure). Still stubbed for later phases: `to_s` (prints "0.0"), `**`,
`Float#coerce`, reverse coercion (`Integer + Float`), `Comparable` mixin,
`%`/`divmod`/`floor(ndigits)`/`round`/`ceil`, and the two front-end limits above.

**Node-tag hazard (fixed, commit bb23de5).** Making float literals self-hosting gave
them an AST node tag `:float` — which collides with the *very common* local variable
name `float`. The closure env-var rewrite (`__rewrite_node_refs`) matches a captured
local's name against a node's children and, without a guard, rewrote the literal's
`:float` head into an `[:index,__env__,k]` read → the decimal was emitted as a raw
String dispatched on as an object → SIGSEGV (turned `core/float/dup_spec` FAIL→CRASH).
Fixed with a position-0 guard (gated on the `e[1]` String payload so a bare `float`
argument is still rewritten). **Lesson: any NEW AST node tag must be added to the
`__rewrite_node_refs` position-0 guards AND the `rewrite_strconst` skip — else it
collides with a same-named captured variable.** See [[compiler_node_tag_var_collision]].

**Payoff of Phase 1 (measured, local `core/float` sweep):** PASS 6→7, CRASH 4→3 after
the node-tag fix; the 3 remaining crashers (`divide`/`inspect`/`to_s`) are all the
pre-existing `to_s`-stub files and clear once Phase 2 item 6 lands. Net zero new float
crashes vs baseline. `float/` arithmetic/comparison/conversion now return real values;
the bulk of remaining FAILs are `to_s`-blocked value checks (Phase 2).

---

## Phase 2 — Easy spec unlocks (mechanical, high density)

Each is small and mostly reuses Phase 1 + a C library call (self-host-safe: the C
runtime does the hard numeric work).

6. **`Float#to_s`/`inspect` v1** — a runtime helper backed by C `snprintf(buf,
   "%.17g", d)` then trimmed, plus explicit `Infinity`/`-Infinity`/`NaN`. This is an
   *approximation* of MRI's shortest-round-trip form (Phase 3 tightens it), but it
   clears `float/to_s` + `float/inspect` from CRASH and passes the common cases.
   **[DONE — this commit]** C helper `__float_to_cstr` (tgc.c) reads the double at
   offset 4 of the Float object, finds the fewest `%.*e` significant digits that
   `strtod`-round-trip, and places the decimal point MRI-style (fixed when the decimal
   exponent ∈ [-4,14] = decpt ≤ DBL_DIG, else `d.dddde±NN` with ≥2 exp digits);
   `Infinity`/`-Infinity`/`NaN`/`-0.0` handled; NaN/Inf detected without libm. `to_s`
   allocates a buffer via `__array` and wraps it with `__set_raw`; `inspect` aliases it.
   **Verified vs MRI on 24 representative values (all exact match)** incl. integer-valued,
   fractions, both scientific boundaries, `-0.0`. Robust inside closures/yield.
   NOTE: the `float/to_s` + `float/inspect` spec FILES still CRASH — but for a
   *pre-existing* harness reason (`send(@method)` + `it_behaves_like` + many literal
   floats in it-blocks), NOT the old stub; my `to_s` is correct where it runs. So the
   sweep crash count is unchanged (no regression), and the real payoff is every OTHER
   spec/site that prints a float. **BUILD NOTE: tgc.c changes require rebuilding
   `out/tgc.o`; the local 32-bit toolchain lacks C headers, so rebuild in the
   `ruby-compiler-buildenv` docker image (`gcc -Wall -m32 -c -o out/tgc.o tgc.c`).**
7. **pack/unpack float directives** (`d D f F e E g G`) in the existing `__Pack`
   codec (`lib/core/pack.rb`) — the raw 8 bytes are already in the object, so pack is
   a byte copy and unpack is `__float_from_bytes`. ~460 assertions.
8. **`sprintf`/`String#%` float conversions** (`%f %e %g %a`) — route to the same
   `snprintf` helper with width/precision/flags. Big chunk of `kernel/sprintf` +
   `string/modulo`.
   IMPL NOTE (next code-tick): today `object.rb:__sprintf` routes `%f %e %g %E %G`
   (types 102/101/103/69/71) ALL through `__format_float(val.to_f, prec)` — pure-Ruby
   FIXED-decimal only, so `%e`/`%g`/`%E`/`%G` are wrong. Fix: add a C helper
   `__snprintf_float(void* obj, char* buf, int conv, int prec)` that builds `"%.*<c>"`
   (c = the conv char, e/E/f/g/G) and `snprintf`s the double at `obj+4`; `%f` may stay on
   the existing `__format_float`. Requires a tgc.o rebuild (docker). Width/flags/`+`/` `/
   `0`/`#` are applied by the surrounding `__sprintf` padding code that already handles
   the integer conversions — reuse it, only the digit-body generation changes.
9. **`Kernel#Float()` + `String#to_f`** — now implementable via C `strtod` (strict
   for `Float()`, lenient/leading-parse for `to_f`). Also `String#to_r` already exists.
   **[DONE — this commit]** C helpers `__str_to_f` (lenient: strtod leading-prefix into
   a fresh Float) and `__float_strict` (whole string modulo whitespace must parse, else
   0). `String#to_f` and `Kernel#Float(arg)` (Integer/Float direct, String strict →
   ArgumentError on junk, else TypeError). Verified vs MRI (lenient prefixes, strict
   raises, whitespace). v1 omits MRI digit-group underscores and the `exception:` kwarg.
10. **`Math` module** — `sqrt exp log log2 log10 sin cos tan atan atan2 pow hypot
    cbrt floor…` each a thin wrapper over the libc `math.h` function (a `%s` C call).
    `math/` ~369 assertions, almost entirely mechanical.
11. **`Float#floor/ceil/round/truncate` (no-arg + integer result)**, `Float#divmod/
    modulo/%`, `Float#step`/`Numeric#step` with a float step, `Float#to_r` (exact
    dyadic rational from the mantissa/exponent — moderate), `Integer#fdiv` finalised.

**Payoff of Phase 2:** the bulk of the ~2,300 assertions. Re-sweep to quantify.

**Sweep-cadence note (ops).** A full local `rubyspec/language rubyspec/core` sweep (2158
files) is compile-bound (~each spec recompiles the whole compiler+lib, ~25s) and
saturates all cores — ~1–2 h wall, during which `lib/core`/`tgc.o` MUST NOT be edited or
rebuilt (in-flight specs would read a half-written state → corrupt results). ax52 (the
intended sweep host) is down. So: rely on the FAST per-commit gates (`make selftest` +
`make selftest-c` + `tools/crash_battery.sh`) for regression safety on every commit, and
run a full local sweep only at a CHECKPOINT (after a few items land), as a dedicated
blocking action — not once per item. Pure-Ruby items (e.g. item 11 floor/ceil/round via
existing Float primitives, no `tgc.o` touch) are the safest to land; C-helper items
(8, 10) need a docker `tgc.o` rebuild and so can't overlap a running sweep.

---

## Phase 3 — Tougher parts (the last mile)

12. **Shortest-round-trip `Float#to_s`.** MRI prints the *shortest* decimal that
    round-trips (`0.1`, not `0.10000000000000001`). Match it (Grisu/Ryu, or the
    classic "increase precision until it round-trips via `strtod`" loop). Needed for
    exact `float/to_s`, `float/inspect`, and `%p`/`inspect` of containers holding
    floats.
13. **IEEE corner semantics:** signed zero (`-0.0`), `NaN`/`Infinity` propagation
    through every op, `Float#round` half-to-even + `ndigits` (positive and negative),
    `Float#{floor,ceil,round,truncate}(ndigits)` returning Float, `Comparable#clamp`
    with NaN, `Float#coerce` edge types, `Float#eql?` vs `==` on `NaN`/`-0.0`.
14. **Bignum↔Float:** `Integer#to_f` for heap integers (convert limb-by-limb),
    `Float#to_i` producing a bignum for large magnitudes, and the exactness rules in
    `Integer#fdiv`/comparison with Float.
15. **`Rational` ⇄ `Float` exactness** (`Float#to_r`, `Float#rationalize`,
    `Rational#to_f` correctly rounded) and **`Complex` with Float components**
    (`abs`/`arg`/`polar`/`rectangular`, `Complex#/`) — these were the pieces the
    2026-07-05 numeric work left stubbed on `to_f`.
16. **`Float#round`/`%`/`divmod` boundary correctness**, `Float::DIG/MANT_DIG/
    MAX/MIN/EPSILON` exact values, and the long tail of `float/` strictness specs
    (TypeError/RangeError on bad coercions, `Float()` error messages).

## Suggested commit cadence

One gated commit per numbered item (1–16), each with a `test/repros/battery/`
guard. Land Phase 1 as a unit first (items 1–5) — nothing below it is useful until
real values flow — then Phase 2 items are independently shippable in any order by
density. Re-run the full `make specs-parallel` sweep at the end of Phase 1 and again
at the end of Phase 2 to measure and update `spec_status.md`.
