# Post-crash-burndown review: cleanup, refactoring & failure triage

**Original review: 2026-07-04**, baseline `01234cd` — PASS 342 / CRASH 10 /
COMPILE_FAIL 5; 5,935 of ~36.9k tests passing.
**Current (2026-07-06, sweep `09872ec`): PASS 376 / CRASH 22 / COMPILE_FAIL 1;
9,302 tests passing.**

The live, authoritative per-file status is the auto-generated
[../spec_status.md](../spec_status.md) (`make specs-parallel`). Active bugs live in
[../KNOWN_ISSUES.md](../KNOWN_ISSUES.md).

This is the maintained synthesis of the 2026-07-04 review. **Its Phase 0–3 plan
(below) has been largely EXECUTED** across the 2026-07-04→06 loop (tests 5,935 →
9,302, ~50 gated commits); it is kept as the record and a map of what remains.
(The six detailed input reports — cleanup / refactoring / docs-hygiene / triage-*
— have been removed now that their actionable items are done and folded into this
doc; per-spec failure detail for the parked projects is regenerable via
`tools/classify_failures.rb` against the current `spec_status.jsonl`.)

## Headline (still true)

The FAIL population is **not dominated by hard problems** — a large share sat
behind trivial/easy lib/core method work, which the loop has now converted. The
genuinely hard buckets (Float, threads, Marshal, Time, encodings, code loading,
pattern matching) are well-bounded and are **parked as dedicated projects**
(table at the end), not loop-tick work.

## Current remaining work (2026-07-06)

Safe incremental lib/core work is **EXHAUSTED** — re-verified 2026-07-06 by wide
MRI-differential probing (compare `ruby x.rb` vs `./compile && ./out/x` on tiny
programs, asserting on VALUES and arg-forms, using LOCALS since `p x.method`
mis-parses) across numeric / Array / Hash / String / Range / Enumerable /
Comparable / Struct / Data / Set / Symbol / Regexp — broad probes now come back
clean. Remaining gaps are all one of:

1. **Pinned compiler bugs** (see KNOWN_ISSUES for repros/signatures): **2b**
   implicit block auto-splat (`[[1,2]].map{|a,b|}`, also blocks `Hash#map`'s
   1-param form — broad block-ABI blast radius, high crash risk); **3c** `Array.[]`
   subclass segfault; **3d** splat + side-effecting block ordering; **3g** bignum
   `heap*heap` multiply wrong for large operands (data-dependent); plus open live
   bugs #4/#5/#7 below.
2. **The CRASH count is LAYOUT-SENSITIVE** (memory `compiler_crash_regression_watch`,
   KNOWN_ISSUES): it wobbles with *every* code change. The deterministic remaining
   crashers are latent **Proc-@addr memory-corruption** EXPOSED — not caused — by
   added code shifting layout (bisected `numeric/quo`'s crash to the mere presence
   of `def quo`). valgrind-in-docker PANICS on it; addresses aren't reproducible
   under `setarch -R`. Do **NOT** whack-a-mole individual crashers or revert
   features to chase the count — the durable fix is the latent-corruption hunt
   (research-grade; entry point documented against the `numeric/quo` repro).
3. **Dedicated projects** — the ceiling is now owned by these (table below).

Everything above requires a *focused, gated* session, not autonomous loop ticks.

## Live bugs from the original review — current status

| # | Bug | Status |
|---|---|---|
| 1 | `instance_exec` routed its first user arg into the block channel (object.rb) | **FIXED `17dffc5`** |
| 2 | `def f(a=1); …; ensure; …; end` crashed (bare `[:block,…]` defm body) | **FIXED `67f79f4`** (R1 normalize_body_shape) |
| 3 | `recv&.m, v` / `f x&.m, v` parse mangled (dot-comma only matched `:callm`) | **FIXED** (R4 step 1) |
| 4 | Op-assign of an env-captured target inside a block leaks a raw AST sexp into the constant scope name | **OPEN** — KNOWN_ISSUES; language/assignments |
| 5 | Stabby lambda with rest-args + nested proc: `__tmp_proc` not declared in the lambda's let | **OPEN** — KNOWN_ISSUES; file/printf `:kernel_sprintf` suite |
| 6 | `MyArray[...]` allocate-based subclass instantiation segfaults self-host | **OPEN** — KNOWN_ISSUES 3c |
| 7 | `__get_raw` unreachable on Array *subclasses* (variables_spec) | **OPEN** — KNOWN_ISSUES; easy standalone |
| 8 | rubyspec_helper failure messages interpolated unset `@result` | **FIXED** (harness matcher batch) |

## Parked as dedicated projects (do NOT pick at in a loop)

The ceiling is owned by these; **Float first** (blocks the most, plus several
remaining CRASH files). Assertion counts are 2026-07-04 estimates.

| Project | Blocked assertions (approx.) | Note |
|---|---|---|
| **Float implementation** | ~2,300+ (float, math, complex, rational, kernel/Float, numeric/step, pack/unpack float dirs, sprintf) | Self-hosting can't compile float literals → needs a compiler change to emit them. Biggest raw payoff. |
| Thread family (real runtime) | ~1,051 | |
| Marshal | 1,339 | largely by-design NotImplementedError |
| Time (zones/strftime) | 1,134 | |
| Encodings | ~1,150 | |
| Code loading (require/load/autoload/eval) | ~700 | dynamic; inherent AOT limits |
| Pattern matching `case/in` | 222 | parser + pattern compiler; KNOWN_ISSUES 2 |
| Regexp engine gaps | ~300 | |
| Wontfix-ish: SyntaxError-via-eval (~38), magic comments (~85) | ~125 | AOT limits |

## Historical: the executed 2026-07-04 plan (for the record)

- **Phase 0 (hygiene) — DONE.** rubyspec_helper matcher batch (ComplainMatcher,
  `be_computed_by`, `have_method`, `with_timezone`, Warning stub, Mock once/twice,
  `@result`→`result`); cleanup commit (DEBUG tripwire at compiler.rb removed, dead
  code/backups purged, canonical repros promoted to `test/repros/`).
- **Phase 1 (structural bug-fix refactors) — DONE.** R1 body-shape normalization
  (fixes live bug #2, kills the 32-file regression class); R4 dot-comma → `:safe_callm`
  (fixes #3).
- **Phase 2 (lib/core conversion sweep) — DONE.** pack/unpack shared codec
  (`lib/core/pack.rb` + binary-safe `String`), Kernel#open, ENV, Symbol delegation,
  Enumerable gap-fill, Array set ops + Hash methods, strict `Kernel#Integer` /
  `String#to_i(base)`, String case/byte family, `module_function`, Set/File/format/
  exception/proc-combinator sweep. Plus the 2026-07-05 differential-probe wins:
  full **Rational** and **Complex** (were near-empty stubs), Integer#quo/remainder
  fix, Rational digit-rounding fix, Array#max(n)/min(n), Range#size, String#to_r /
  delete_prefix|suffix, block-less Array-iterator Enumerator guards, full Hash/Array
  Enumerable surfaces.
- **Phase 3 (localized compiler/runtime) — PARTIALLY DONE.** Glob engine
  (`lib/core/glob.rb`) done; `class X < <localvar>` runtime superclass done
  (`c538602`, KNOWN_ISSUES 3h fixed). Still open: defined? coverage, `$!/$@` /
  regexp match globals, qualified-const op-assign (#4), destructuring protocol
  (#7), kwargs super-forwarding, Enumerator::Lazy+product, the `__tmp_proc` lambda
  bug (#5), the `MyArray` segfault hunt (#6).
- **Phase 4 (structural refactors) — NOT STARTED** (as capacity allows): R2 unified
  scope-boundary predicate over the ~10 hand-maintained walkers (highest leverage
  vs regression recurrence); R5 preprocess pass manifest; R10 truthiness
  centralization; opportunistic R6–R9 (build the parsetree-diff harness first).

Beyond landed lib/core: binary-safe String, the Dir#read dirent-aliasing
memory-corruption fix, and a codegen-hazard playbook (memory
`compiler_analysis_loop_2026_07_05`). Reverted as layout-sensitive: `&nil`
forwarding compiler-side fixes (KNOWN_ISSUES 3b) and a vtable module-override for
`Comparable#==` — do NOT retry flattened-vtable ancestry fixes without real method
resolution (HARD LESSON in memory).
