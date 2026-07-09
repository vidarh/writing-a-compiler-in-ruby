# Ruby Compiler TODO

**Last Updated**: 2026-07-09

## Test Status

Current numbers live in the auto-generated **[spec_status.md](spec_status.md)**
(do not copy them here — they rot). Selftest: both gates (`make selftest` + `make selftest-c`)
green, always (hard commit requirement). The CRASH count includes a PRE-EXISTING flaky
Class.new-with-ivars heap corruption (see [[compiler_class_new_ivars_heap_corruption]]) — the
2026-07-09 reflection work shifted layout and flipped 3 specs FAIL→CRASH without a new defect.

## Compile speed: COREMARSHAL — DONE (2026-07-09)

The binding constraint was compile speed (lib/core re-parsed on every spec compile). SOLVED:
- **COREMARSHAL AST cache** — a reflection-free serializer caches lib/core's parsed AST; the parallel
  sweep generates it once (`COREMARSHAL_DUMP`) and reuses it (`COREMARSHAL_AST`) for every compile.
  ~50% faster per-spec compile, byte-identical output, default ON (`COREMARSHAL=0` disables).
- **Dynamic-ivar reflection** — real `instance_variable_*` via a compiler-emitted `__ivar_table`; the
  keystone that (with the const reflection table) also enabled full Marshal.
- **Full Marshal** — dump/load byte-identical to MRI for nil/bool/int/string/symbol/array/hash/float +
  custom objects + marshal_dump/_dump; the temporary custom serializer is to be replaced by it.
This is a TEMPORARY stage until Marshal serializes lib/core's AST directly; see
[[compiler_mri_selfhost_never_diverge]] and docs/MARSHAL_REFLECTION_PLAN.md.

## Next
- Fix the pre-existing Class.new-with-ivars heap corruption (canary hunt) — clears 3 crashers.
- Marshal tail: bignum 'l' (blocked on 2**30/heap-multiply), Struct 'S' (blocked on naming a class
  assigned to a constant), object-links, nested-constant const_get.
- Scanner rewrite step 2 (−39% alloc / less GC pressure) — now SECONDARY since core parse is cached.

---

## Priority 1 — DONE (2026-07-04→06)

Phases 0–2 and most of Phase 3's easy items are complete: rubyspec_helper matcher
batch; cleanup commit (DEBUG tripwire removed, backups purged, canonical repros in
`test/repros/`); R1 defm-body shape normalization; R4 `:safe_callm` dot-comma;
pack/unpack codec (`lib/core/pack.rb` + binary-safe String); the lib/core sweeps
(Kernel#open, ENV, Symbol, Enumerable, Array/Hash methods, strict `Integer()`,
String case/byte, module_function); the glob engine (`lib/core/glob.rb`); full
Rational/Complex, Integer#quo, Range#size, block-less enumerator guards, and
`class X < <localvar>` runtime superclass. Safe lib/core work is now EXHAUSTED.

## Priority 2: remaining localized compiler/runtime work (Phase 3)

- defined? coverage; $!/$@ + regexp match globals; qualified-constant op-assign
  (live bug #4); block-param/masgn destructuring incl. implicit auto-splat
  (KNOWN_ISSUES 2b — BROAD block-ABI blast radius, high crash risk); kwargs super
  forwarding; Enumerator::Lazy; the __tmp_proc stabby-lambda bug (#5); MyArray
  subclass segfault (#6, KNOWN_ISSUES 3c); bignum heap*heap multiply (3g).
- super() in define_method: `define_method(:name) { super() }` needs the method
  name from the define_method argument, not scope lookup. Related: `return` inside
  a define_method'd proc needs method-return semantics.
- **The 7 remaining CRASH specs are now CHARACTERIZED** (2026-07-09, via the __alloc probe +
  crash-log capture — see [[compiler_crash_regression_watch]]). They are NOT one latent
  corruption: array/sort was FIXED (Integer ops via public `<=>`); the rest are distinct deep
  bugs — send (multi-assign lvalue), return (define_method-from-proc + return-in-ensure),
  instance_eval/exec (nested-const + string-eval CVar), regexp/escapes (eval+regex),
  pattern_matching (guard-scope binding); plus module/autoload which OSCILLATES 6↔7 with layout.
  Each has a minimal repro + fix direction in memory. Do NOT whack-a-mole; pick one as a plan.

## Priority 3: projects (parked; schedule deliberately)

- **Float — DONE** (core/float 94%, complex 91%, math 93%; see
  [FLOAT_SUPPORT_PLAN.md](FLOAT_SUPPORT_PLAN.md)). Remaining tails are bignum-multiply (round),
  the `%e/%g` sprintf C helper, and two deep codegen edge specs — not a "project".
- **Dynamic-ivar reflection** (new; the compile-speed keystone above — promote to a plan).
- Bignum heap*heap multiply (unblocks gcd/lcm/ceildiv/rational-to_f/float-round).
- Time (zones/strftime), Thread family, code loading, encodings, pattern matching (full),
  Marshal (needs the reflection above), eval (AOT limits), Regexp engine
  ([REGEXP_IMPLEMENTATION_PLAN.md](REGEXP_IMPLEMENTATION_PLAN.md)).

---

## Testing Commands

```bash
make selftest        # Must pass before any commit
make selftest-c      # Must pass before any commit
./run_rubyspec rubyspec/language/some_spec.rb   # One spec file
make specs-parallel  # Full sweep (updates docs/spec_status.*)
```

## References

- **[review/ANALYSIS.md](review/ANALYSIS.md)** — ranked plan (start here)
- **[KNOWN_ISSUES.md](KNOWN_ISSUES.md)** — active bug documentation
- **[DEBUGGING_GUIDE.md](DEBUGGING_GUIDE.md)** — debugging techniques
