# Ruby Compiler TODO

**Last Updated**: 2026-07-09

## Test Status

Current numbers live in the auto-generated **[spec_status.md](spec_status.md)**
(do not copy them here — they rot). As of 2026-07-09: PASS 545 / ~10,900 tests, CRASH 7.
Selftest: both gates (`make selftest` + `make selftest-c`) green, always (hard commit
requirement).

## Current top priority: COMPILE SPEED

Per [NEXT_STEPS.md](NEXT_STEPS.md), the binding constraint is now compile speed — lib/core is
re-parsed/re-compiled on every spec (~11s contended / ~2s idle per compile; a sweep pays it 2158×).
The keystone is **dynamic-ivar reflection**, which lands the COREMARSHAL ~42% compile speedup AND
the `define_method`→vtable stub-override that unblocks the numeric/complex mock cluster. See
NEXT_STEPS §A6 and [[compiler_mri_selfhost_never_diverge]].

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
