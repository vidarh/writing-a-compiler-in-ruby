# Post-crash-burndown review: cleanup, refactoring & failure triage

Date: 2026-07-04. Baseline: commit `01234cd` — PASS 342 / FAIL 1797 / CRASH 10 /
COMPILE_FAIL 5 / TIMEOUT 4 files; 5,935 of ~36.9k individual tests passing.

Six detailed reports in this directory feed this synthesis:

| Report | Scope |
|---|---|
| [cleanup.md](cleanup.md) | Non-structural cleanup (comments, dead code, debris) |
| [refactoring.md](refactoring.md) | Structural refactoring (R1–R12, ranked) |
| [docs-hygiene.md](docs-hygiene.md) | Documentation staleness & missing docs |
| [triage-language.md](triage-language.md) | language/ failures (1,890 tests, 68 files) |
| [triage-core-a-h.md](triage-core-a-h.md) | core/array..hash (10,265 failed assertions) |
| [triage-core-i-z.md](triage-core-i-z.md) | core/io..warning (17,637 failed examples) |

## Headline

The FAIL population is **not dominated by hard problems**. Roughly a third of all
failing assertions sit behind trivial/easy missing-method work in lib/core plus a
handful of rubyspec_helper gaps, and the two single biggest items (pack/unpack,
~4,900 assertions) share one codec. The genuinely hard buckets (Float ~2,300+,
threads ~1,050, Marshal 1,339, Time 1,134, encodings ~1,150, code loading ~700,
pattern matching 222) are well-bounded and should be *scheduled as projects*, not
picked at during a burndown loop.

## Live bugs found by this review

| # | Bug | Status |
|---|---|---|
| 1 | `instance_eval`/`instance_exec` missing `blkarg` in `__call_with_self` — instance_exec routed its first user argument into the block channel (object.rb:633/637) | **FIXED, committed `17dffc5`** (gates green: selftest/selftest-c Fails: 0, battery 98/98) |
| 2 | `def f(a = 1); ...; ensure; ...; end` crashes at runtime — `rewrite_default_args` is a THIRD pass mishandling the bare `[:block, args, stmts, rescue, ensure]` defm body, splicing `:block` in as a statement | Open — fixed structurally by **R1** (body-shape normalization) |
| 3 | `a, b = recv&.m, v` and `f x&.m, v` still parse mangled — dot-comma normalization matches only `:callm`, not `:safe_callm` | Open — fixed by **R4 step 1** |
| 4 | Op-assign of an env-captured target inside a block leaks a raw AST s-expression into the constant scope name (`uninitialized constant [:index,[:index,:__env__,1],3]::A`) | Open — language/assignments; part of triage C5 |
| 5 | Stabby lambda with rest-args whose body creates a nested proc: `__tmp_proc` not declared in the lambda's let → `undefined method '__tmp_proc'` — gates 253 fails in file/printf + the shared :kernel_sprintf suite | Open — same family as the fixed rewrite_lambda bugs (transform.rb:1050 region) |
| 6 | `Array.[]`/subclass instantiation (`MyArray[...]`): allocate-based implementations segfault the self-hosted compiler (array.rb:463 comment) — gates ~40 array spec files | Open — compiler bug hunt, medium/hard |
| 7 | `__get_raw` unreachable on Array *subclasses* (7× in variables_spec) | Open — easy standalone |
| 8 | rubyspec_helper.rb:556 failure messages interpolate unset `@result` (always nil) | Open — one-line, in harness batch |

## Recommended next-session plan (ease × payoff)

Phase ordering interleaves "protect the codebase" items (R1/R4, which fix live
bugs) with the highest-density test conversions. Assertion counts are estimates
from the triage reports.

### Phase 0 — hygiene batch (half a day, no compiler risk)
1. **rubyspec_helper gap batch** (trivial, one file): fix `ComplainMatcher` (always
   returns true → every `should_not complain` fails), add `be_computed_by`,
   `have_method`/`have_instance_method`/`have_constant`/`be_ancestor_of`,
   `with_timezone`, `suppress_keyword_warning`, a `Warning` module stub, Mock
   `once`/`twice`, and the `@result`→`result` message fix. **~80–130 direct passes
   plus it un-gates the pack/unpack data tables (~25 spec files abort on
   `be_computed_by`) and ~100 pattern-matching tests.** Do first; de-noises
   everything after.
2. **Cleanup commit** (from [cleanup.md](cleanup.md) top-15): delete the live DEBUG
   tripwire at compiler.rb:913–914, ~30 commented-out debug/dead lines, duplicate
   `Array#collect!` stub, stale ABI/"MISSING FEATURES"/"no-op" comments
   (transform.rb:451/1405, exception.rb:40–44, class.rb:310–324), editor backups
   in lib/core/ + test/ (~20 files that poison greps), tmp/ purge keeping the six
   canonical repros (bk6, hop1, ac2, st5, mc6, blk1 — promote to test/repros/),
   root litter (`selftest_errors.tmp` tracked-empty, `foo^bar/`, stray
   `rubyspec_temp_*`). All non-structural; one gate run for the source-file edits.

### Phase 1 — structural bug-fix refactors (1–2 days, do BEFORE feature work)
3. **R1: normalize the defm/proc body shape once, early** (2–4h) — one
   canonicalization pass wrapping bare `[:block,...]` bodies; deletes the two
   existing per-pass compensations and fixes live bug #2. Kills the whole
   32-file-regression class.
4. **R4 step 1–2: extend dot-comma normalization to `:safe_callm`** (~1 day) —
   fixes live bug #3 (two parse mangles), then delete the now-dead `:callm`
   unmangle branches behind a raise-if-hit assertion period.
5. **R3: self-host miscompile corpus** (1–2 days, test-only, zero product risk) —
   extract the ~14 frozen miscompile repros living only as FIXME comments
   (ternaries, `seen |= x`, defaulted recursive params, one-lining) into
   `spec/selfhost/` run under compile2. Converts folklore into checkable rules;
   every later refactor's risk budget depends on it.

### Phase 2 — lib/core conversion sweep (~1 week, ~4,500–5,500 assertions)
Ordered by density; all pure lib/core (+harness), no compiler changes:

| Item | Est. converts | Effort |
|---|---|---|
| 6. **pack/unpack integer+string directives** — one shared width×endianness codec for `Array#pack` (only C/c/a/A/Z exist; silently skips the rest) and `String#unpack` (stub returning `[]`) | **~4,900** (2,583 pack + 1,955 unpack + 358 string dirs; float dirs stay in the Float bucket) | medium, mechanical |
| 7. Kernel#open → File.open / IO.popen delegation | ~300–440 | trivial |
| 8. ENV hash-like methods (snapshot→Hash→delegate→write back) | ~320 | trivial |
| 9. Symbol string-delegation sweep (slice/[]/inspect/match/casecmp) | ~240 | trivial |
| 10. Enumerable gap-fill (none?/one?/tally/grep/first/take/to_h...) | ~400 | easy |
| 11. Array set ops (&,\|,-,union...) + Hash small methods (<,<=,assoc,transform_keys!...) | ~395 | trivial/easy |
| 12. Strict Kernel#Integer + String#to_i(base) — one shared numeric parser | ~180–250 | easy |
| 13. String case/byte family (casecmp, byteindex, bytesplice...) | ~250 | trivial/easy |
| 14. `module_function` real implementation (bare-modifier form needs compile-time mode tracking) | ~100 | easy-medium |
| 15. Set method sweep; File path methods (basename suffix, dirname level); format-engine validation (ArgumentError/TypeError/KeyError + Float::NAN/INFINITY constants); exception introspection (full_message etc.); proc/method combinators (curry, >>, <<) | ~1,000 combined | easy grind |

### Phase 3 — medium, well-localized compiler/runtime work
- **defined?** coverage gaps (~43, one code path); **$!/$@** wiring (~40, exception
  runtime); **qualified-constant assignment + op-assign** (~55, includes live bug
  #4); **destructuring protocol** — `|(a,b)|` block params + masgn to_ary (~75,
  start with the easy `__get_raw` subclass bug #7); **kwargs correctness** incl.
  super forwarding (~85, one coherent workstream); **glob engine**
  (Dir.glob/Dir.[]/File.fnmatch, ~436, self-contained new core file); **regexp
  match globals** `$~ $& $1..` (~50, frame-local semantics); **Enumerator::Lazy +
  product** (~340); **Module#const_get** over the existing runtime constant
  registry (~155); the **__tmp_proc lambda bug** (#5, gates 253); the **MyArray
  segfault hunt** (#6, un-gates ~40 array files); strictness long tail
  (TypeError/FrozenError/visibility raises, ~100+ rolling filler).

### Phase 4 — remaining structural refactors (as capacity allows)
- **R2** unified scope-boundary predicate over the TEN hand-maintained walkers
  (2–3 days, highest leverage against regression recurrence; stage it).
- **R5** preprocess pass manifest with ordering-constraint tests (0.5–1 day).
- **R10** truthiness centralization + `:raw` type naming (0.5–1 day).
- Opportunistic: R6 call-arg canonicalization, R7 compile_call/callm helpers,
  R8 splat-prologue unification (build the parsetree-diff harness first — it
  benefits every transform.rb change), R9 get_arg tightening.

### Park as dedicated projects (do NOT pick at in a loop)
| Project | Blocked assertions (approx.) |
|---|---|
| **Float implementation** | ~2,300+ (float/ 452, math 369, complex 310, rational ~259, kernel/Float 297, numeric/step 205, pack/unpack float dirs ~460, sprintf halves...) — unblocks 4 of the 10 remaining CRASH files too |
| Thread family (real runtime) | ~1,051 |
| Marshal (by-design NotImplementedError) | 1,339 |
| Time (zones/strftime) | 1,134 |
| Encodings | ~1,150 |
| Code loading (require/load/autoload/eval) | ~700 |
| Pattern matching `case/in` (parser + pattern compiler) | 222 |
| Regexp engine gaps | ~300 |
| Wontfix-ish: SyntaxError-via-eval (~38), magic comments (~85) | ~125 |

## Docs work (from [docs-hygiene.md](docs-hygiene.md), suggested order)
1. KNOWN_ISSUES.md + TODO.md: delete the FIXED break-target and `proc{|&b|}`
   entries (both resolved by the nested-env/`__callblk__` rework), point stats at
   auto-generated spec_status.md (they still say "3 files passing, 27%" from
   2026-02-10).
2. improvement-planner.md: retire the `make rubyspec-*` / `docs/rubyspec_*.txt`
   section — it actively misguides the planner agent.
3. **Write docs/CLOSURES.md** — the closure environment design (env layout,
   `__wrapenv`, hops, lambda ABI/`__callblk__`, break/preturn/ensure semantics,
   walker scope-boundary rules). Largest undocumented subsystem; the 620a91b
   regression was four walkers disagreeing about exactly this.
4. CLAUDE.md / ARCHITECTURE.md: exceptions & regexp are implemented; local
   toolchain (not Docker) is the default compile path.
5. README_RUBYSPEC.md rewrite as a harness reference; DEBUGGING_GUIDE refresh
   (exceptions exist, tmp/ paths, `setarch -R`/valgrind-in-docker techniques).
6. Plans sweep: archive BGFIX/YIELDFIX (obsoleted by 63b5875), re-validate the
   other ~20 active plans, resolve the PEEPFIX contradiction.

## Expected payoff summary

Phases 0–2 are ≈1.5–2 weeks of low-risk work converting an estimated
**~6,000–7,000 failed assertions (~20% of all failures)** and fixing 4 live bugs,
while phase 1 removes the two structural traps (body shape, walker agreement)
that caused this session's only regression. Phase 3 adds roughly another ~1,400.
Beyond that, the ceiling is owned by the parked projects — **Float first** (it
blocks the most assertions AND 4 of the 10 remaining crash files).
