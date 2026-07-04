# Ruby Compiler TODO

**Last Updated**: 2026-07-04

## Test Status

Current numbers live in the auto-generated **[spec_status.md](spec_status.md)**
(do not copy them here — they rot). Selftest: both gates green, always
(hard commit requirement).

The prioritized work plan is **[review/ANALYSIS.md](review/ANALYSIS.md)**
(2026-07-04): phased ease-vs-payoff ranking covering harness gaps, the
pack/unpack codec, lib/core method sweeps, structural refactors R1–R12, and
the parked projects. This file only tracks the headline order.

---

## Priority 1: current phase (from review/ANALYSIS.md)

1. ~~Phase 0a: rubyspec_helper matcher/helper batch~~ (DONE 6ec0a6f)
2. Phase 0b: cleanup commit (dead code, stale comments, backup-file purge —
   docs/review/cleanup.md top-15)
3. Phase 1: R1 defm-body shape normalization (fixes live default-arg+ensure
   crash); R4 safe_callm dot-comma normalization (fixes two live parse bugs);
   R3 self-host miscompile corpus in spec/selfhost/
4. Phase 2: pack/unpack integer codec (~4,900 assertions) + lib/core trivial
   sweeps (Kernel#open, ENV, Symbol, Enumerable, Array/Hash small methods,
   strict Integer(), String case/byte, module_function)

## Priority 2: medium, localized (Phase 3)

- defined? coverage; $!/$@ wiring; qualified-constant assignment + op-assign;
  block-param/masgn destructuring protocol; kwargs correctness (incl. super
  forwarding); glob engine; regexp match globals; Enumerator::Lazy;
  Module#const_get; the __tmp_proc stabby-lambda bug; MyArray segfault hunt.
- super() in define_method: `define_method(:name) { super() }` needs the
  method name from the define_method argument, not scope lookup. Related:
  `return` inside a define_method'd proc needs method-return semantics.

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
