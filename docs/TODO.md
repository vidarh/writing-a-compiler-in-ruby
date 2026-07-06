# Ruby Compiler TODO

**Last Updated**: 2026-07-06

## Test Status

Current numbers live in the auto-generated **[spec_status.md](spec_status.md)**
(do not copy them here — they rot). Selftest: both gates green, always
(hard commit requirement).

The prioritized work plan is **[review/ANALYSIS.md](review/ANALYSIS.md)**; its
Phase 0–3 plan has been largely executed (tests 5,935 → 9,302). This file tracks
the current headline order.

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
- **CRASH count is LAYOUT-SENSITIVE** (KNOWN_ISSUES; memory
  compiler_crash_regression_watch): the remaining deterministic crashers are
  latent Proc-@addr corruption exposed by layout shifts. Do NOT whack-a-mole
  individual crashers; the fix is the latent-corruption hunt (research-grade).

## Priority 3: projects (parked; schedule deliberately)

- **Float** — biggest single blocker (~2,300+ assertions, 4 of 10 remaining
  CRASH files). Do first among the projects.
- Time (zones/strftime), Thread family, code loading, encodings, pattern
  matching (full), Marshal (by design), eval (AOT limits).

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
