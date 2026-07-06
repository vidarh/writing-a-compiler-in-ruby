# Next Steps — Completing the Compiler

> **⚠ STALE STATE (2026-06-26 roadmap).** The state figures below (e.g. "~4% files
> pass", "27% tests") are the ORIGINAL baseline and are long superseded — current
> status is PASS 376 / 9,302 tests passing (@ `09872ec`); see [spec_status.md](spec_status.md)
> and [review/ANALYSIS.md](review/ANALYSIS.md). The strategic framing may still be useful;
> the numbers are not.


*Created: 2026-06-26. A cross-cutting roadmap proposal. Each numbered item below is
intended to be promoted into a focused `docs/plans/<CODE>` plan via the improvement
planner; this document is the strategy that prioritizes them (an iterative loop, not a
fixed order — see Operating method).*

> **The standing operating procedure lives in [`docs/COMPILER_WORKFLOW.md`](COMPILER_WORKFLOW.md)** —
> read that first on a restart, then this file for the candidate backlog and detail.

## The gate — non-negotiable

**Every change is gated by BOTH `make selftest` AND `make selftest-c` passing with ZERO
failures.** `selftest-c` is the survival gate: if it fails the compiler can no longer
compile itself correctly — it is **broken** and all other progress is blocked until it is
fixed. Never commit on a red gate; never explain a failure away. See
[`docs/COMPILER_WORKFLOW.md`](COMPILER_WORKFLOW.md).

## Priorities (from the user)

0. **THE GOAL is to complete the compiler** — a correct, self-hosting, pure-Ruby compiler
   that passes (ideally unmodified upstream) rubyspec. Everything below is a facet of that.
1. **Spec-run speed is the current top priority *because it is the binding constraint*** on
   the correctness burndown that completes the compiler — not because speed is the goal. A
   fast, measurable loop makes every later correctness fix affordable. As the loop gets
   fast, weight shifts back to direct correctness/feature/GC/codegen work.
2. **Measure first.** Benchmarks and structured spec results come before optimizing — an
   unmeasured speedup claim (e.g. "the compiler dominates the loop") is speculative until
   measured. **And the benchmark must measure what matters: real rubyspec runs end-to-end
   (preprocess → compile → link → run, with real pass/fail/crash/timeout outcomes), not
   proxy inputs.**
3. **Spike-driven.** Before committing to expensive work, run a quick **spike to verify
   the complexity/payoff**. Apply the cheapest effective win first; shelve a candidate
   the moment a faster-to-apply alternative exists.
4. **Pure Ruby only**, using the `%s(...)` s-expression extension. The C GC (`tgc.c`)
   is a tolerated *exception* we aim to delete. No new C.
5. **Token-efficient**: push as much as possible into deterministic scripts/reusable
   tools so Claude spends tokens fixing, not rediscovering.
6. There is an **idle machine** available for parallel test builds, reachable via
   `ssh compiler@ax52`.
7. **Minimise rubyspec divergence.** The goal is to track upstream `ruby/spec` and
   eventually run it **unchanged** under real mspec. Today's divergence is bad: the
   `run_rubyspec` runner *actively rewrites spec files* (sed-injecting parens into
   `describe`, rewriting `@ivars` to `$globals`, stripping `platform_is`/`ruby_bug`
   args, etc.). Any new tooling — including machine-readable output — must live in the
   **harness layer, never in the spec files**, and should reduce rewrites, not add to them.

## Operating method — a continuous loop, *not* a fixed order

We do **not** lock into addressing one issue at a time in a predetermined sequence.
Each iteration re-ranks *all* candidates against the latest data and picks the best
payoff/effort available right now. The loop:

1. **Benchmark.** Run the measurement harness (Workstream 0) — per-stage timings plus a
   fixed spec set. This produces hard numbers for everything that *can* be measured.
2. **Estimate the un-benchmarkable.** Some potential can't be measured until it's built —
   most of Workstream C (codegen). *Guess* its payoff from cheap proxies: static
   instruction-count / `tools/asm_*` n-gram analysis of wasted patterns, fraction of
   emitted ops a change would touch, etc. A rough estimate is enough to rank against
   measured wins — we are choosing what to *try*, not committing.
3. **Pick low-hanging fruit first.** Rank the whole candidate pool — measured (step 1) and
   estimated (step 2), across *every* workstream — by payoff ÷ effort, and take the
   cheapest effective win. Big-ticket items (e.g. A6 Marshal precompile) earn a slot only
   when a quick **spike** says the payoff justifies the cost *and* nothing cheaper is left.
4. **Iterate — including re-benchmarking.** Apply the win, re-run the benchmark (numbers
   shift; a stage that wasn't the bottleneck may become one), re-estimate, re-rank. The
   ranking is expected to churn; that's the point.

**Burndown is interleaved, not a phase.** When a speedup surfaces a compiler bug (faster
or changed compilation paths tend to): `git stash` the speedup, use Workstream B tooling
to **identify the relevant specs and make them green**; if it still blocks, write a
**separate minimal test** (`create-minimal-test`) or **simplify the offending code**, then
resume. Every few iterations, run *different* parts of rubyspec as benchmarks and scan for
low-hanging fruit (cheap speed *or* correctness wins), which also keeps the benchmark set
representative as coverage grows.

---

## Where things stand

Facts below are either directly verified (✓) or **estimated and not yet measured (≈)** —
the latter are exactly what Workstream 0 exists to confirm or refute.

| Area | State |
|---|---|
| Language specs ✓ | ~4% files pass (4/80); 27 fail, 48 **crash**, 1 compile-fail. 269/982 tests pass (27%). |
| Spec loop cost ≈ | *Estimated* `ruby driver.rb` ≈ 2.8 s/spec (claimed dominant); `gas`+`ld` ≈ 0.4 s; run 1–30 s. **Unmeasured — no per-stage instrumentation exists.** |
| Why compile is slow ✓ | `lib/core` (~48 files) is re-parsed **and re-codegen'd into every spec binary**. Only `out/tgc.o` is cached. (Time impact is the ≈ estimate above.) |
| Crash waste ✓ | Sequential runner, **30 s timeout** per spec → up to ~24 min/run lost to the 48 crashers alone. |
| Hardware ✓ | 16 local cores + idle remote box. Runner is **fully sequential** today. |
| Harness ✓ | Custom `rubyspec_helper.rb` shim (not mspec) + stdout-grep in `run_rubyspec`; mspec present but not runnable by the compiler yet. |
| Codegen ✓ | Crude: redundant `mov`s, no scaled addressing, push/pop spilling, over-allocated call frames, 6-rule peephole, no constant folding. `tools/asm_*` metric scripts already exist. |
| GC ✓ | Conservative mark/sweep in C, **currently disabled** (`tgc_start` commented out → leaks). s-expr `__alloc/__realloc` abstraction already in place. |
| Repo ✓ | Root holds 79 tracked + ~68 untracked files: dead 2014–2016 emacs lock symlinks, `debug_*.rb` scratch, temp specs, `.gitignore~`, `.s`. `docs/plans` bloated with timestamped snapshots. |
| Planning ✓ | Mature system: 20 active plans, 6 goals (CODEGEN, COMPLANG, SELFHOST, PARSARCH, PURERB, MULTIARCH). No existing plan covers test speed/parallelization or a burndown-tooling pipeline. |

The leading hypothesis — **the spec loop is compiler-bound, not toolchain-bound, and is
embarrassingly parallel** — is plausible but *must be measured before we optimize on it.*

---

## Workstream 0 — Benchmarks (foundational; **do this first**)

Without benchmarks every proposal here is speculative. Build the measurement harness
before touching any optimization, and commit its output so changes are tracked over time.

### 0.1 Per-stage timing instrumentation
Instrument the pipeline to report wall-clock for each stage — **parse → transform →
codegen → `gas` → `ld` → run** — per spec and aggregated. This turns the ≈2.8 s estimate
into real numbers and tells us *which* stage to attack (parsing? codegen? linking?).
Without it we could spend days optimizing a stage that isn't the bottleneck.

### 0.2 A fixed benchmark set
Pick a small, stable, representative slice (e.g. a fixed handful of language + core specs
plus `selftest`) timed end-to-end and per-stage. Reproducible inputs, committed results
file (mirroring how `tools/asm_*` / `docs/asm_baseline.txt` track codegen size). This is
the yardstick every Workstream A change is measured against.

### 0.3 Low-hanging-fruit harness
A periodic pass (per the operating method) that runs *different* parts of rubyspec and
flags cheap wins in the output — both speed (a stage spiking on some construct) and
correctness (clusters of identical failures). Output feeds Workstream B's classifier.

> Workstream 0 is the gate: **A-items are only prioritized by what 0.1 actually shows.**

---

## Workstream A — Make the spec loop fast (TOP PRIORITY)

Benchmark-guided (Workstream 0). Apply cheapest effective win first; each item gets a
**spike to verify payoff** before heavy investment. The ordering below is the *current
hypothesis* — 0.1's measurements may reorder it.

### A1. Parallel + remote spec runner *(biggest immediate win)*
Spec compilations are fully independent. Build `run_rubyspec_parallel` (wrapping the
existing per-spec logic) taking `-j N`:
- Each worker writes to a private `out/<worker>/` to avoid `.s` clobbering; `tgc.o`
  is read-only and shared.
- Fan out with GNU `parallel`/`xargs -P`. 16 cores → ~10–14× wall-clock improvement.
- **Remote box**: `parallel --sshlogin` (the repo + `toolchain/32root` are self-contained
  since LOCALDEV removed the Docker requirement — the remote just needs a checkout).
  Split the file list across local + remote, merge results.
- Keep a thin `make rubyspec-language` etc. that calls the parallel runner so existing
  habits still work.

### A2. Cut crash latency
Crashes currently burn up to 30 s each. Specs are tiny:
- Drop the per-spec timeout to **3–5 s** (configurable).
- Detect segfault via **exit code immediately** instead of waiting; only the timeout
  path should wait. Reconsider whether the `script -q -c` wrapper is still needed.
- Expected: tens of minutes → low single digits, before parallelism even helps.

### A3. Machine-readable results — *from the custom harness, zero spec edits*
**Current reality (verified):** the specs do **not** run under mspec. `run_rubyspec`
swaps the upstream `spec_helper` require for `require 'rubyspec_helper'` — a hand-rolled
`describe`/`it`/`.should`/mock shim in the repo root — then *greps the compiled binary's
stdout* for a `"X passed, Y failed, Z skipped (N total)"` line. mspec is present under
`mspec/lib`, but the compiler cannot yet run it; that is precisely why the shim exists,
and getting real mspec to run is a separate long-term goal (per CLAUDE.md). So there is
no mspec formatter to hook today.

The structured output therefore belongs in the **existing harness layer**, split between:
- **`rubyspec_helper.rb`** — already tallies passed/failed/skipped, so have it emit a
  **JSONL record** (instead of, or alongside, the human summary the runner greps). This
  replaces brittle stdout-grepping with a record the framework already holds.
- **`run_rubyspec`** — wraps the cases the shim never reaches: compile failure and
  runtime crash (no summary emitted), supplying `phase`/`exit`/`signature`.

```
{ "spec": "...", "phase": "compile|run|ok", "passed": N, "failed": N, "skipped": N,
  "exit": 139, "signature": "<normalized error/crash key>",
  "rewrites": ["describe-parens","ivar-to-global"], "examples": ["..."] }
```
- **Zero spec edits** (constraint 6): this changes the *shim and runner*, never the spec
  files, and introduces **no new sed rewrites**.
- When the compiler can eventually run real mspec, this logic becomes an ordinary mspec
  formatter and `rubyspec_helper.rb` retires with the rest of the custom runner — the
  specs stay pristine throughout.

The `"rewrites"` field records which existing sed workarounds a spec currently depends
on — feeding A4.

### A4. Treat the spec rewrites as a divergence burndown list
The sed transformations in `run_rubyspec` are not infrastructure — each one is a
**compiler bug** papering over a real defect (paren-less `describe` won't parse,
`@ivars` are broken, `platform_is(hash)` args won't parse…). They are also the largest
source of divergence from upstream.
- Enumerate every active rewrite into a tracked list with the underlying defect and the
  specs that depend on it (the A3 `"rewrites"` field makes this measurable).
- Make **"number of active rewrites"** a first-class KPI driven toward zero — fixing the
  parser/ivar bug behind a rewrite lets us *delete* that rewrite, moving us toward
  running unchanged upstream specs.
- This is a high-value burndown category in its own right: it overlaps the parser-first
  ordering in B2 and directly serves the long-term "unmodified upstream" aspiration.

### A5. Scoped re-runs for the inner loop *(not caching)*
Result caching keyed on the compiler/lib hash would be pointless: during burndown the
compiler **always** changes — that's *why* a re-run happens — so such a cache would miss
every time. The lever isn't "skip unchanged specs"; it's **run a smaller set during
iteration**:
- The runner takes an explicit spec list / glob so the inner loop re-runs only the
  handful of specs in the signature being worked (seconds, even serially).
- A **full** parallel run (A1) is the commit gate — cheap enough after A1/A2 that there's
  no need to be clever about which specs "might" be affected (a compiler change can
  affect anything, so a partial regression run is unsafe before committing).

### A6. Pre-compiling `lib/core` via Marshal *(spike candidate — potentially the biggest win)*
`lib/core` is re-parsed and re-codegen'd identically into every spec binary (~80×/run).
If 0.1 confirms compilation dominates, eliminating that repetition is the **largest
structural win available** — so it is back in scope, gated on a spike.

**Why it isn't trivial** (the real blocker, not label collisions): compiling the spec
code needs the full **in-memory symbol state** the compiler builds *while* compiling
`lib/core` — class/method tables, vtable & ivar layouts, constants. A linked `core.o`
gives the runtime the code but gives the *compiler* none of that state. The prerequisite
is **serializing the compiler's internal data-structure graph** (symbol tables, scopes,
layouts) after compiling core once, then reloading it per spec instead of recompiling.

**Why it may now be cheap — Marshal:** that serialization is exactly what `Marshal`
provides. The user maintains a **pure-Ruby Marshal** (`https://github.com/vidarh/pure_ruby_marshal`)
as a starting point — and pure-Ruby aligns with constraint 3 / the eventual self-hosted
path where MRI's `Marshal` won't exist in compiled code.

**Spike (do before any heavy investment):**
1. After compiling `lib/core` under MRI, `Marshal.dump` the compiler's symbol/scope state;
   for a spec, `Marshal.load` it and compile only the spec against it. **Use MRI's
   built-in `Marshal` first** — it's the cheapest way to test the *hypothesis* (is the
   state serializable at all — cycles/procs? and is load faster than recompiling core?).
2. If the hypothesis holds, adopt **`pure_ruby_marshal`** for the pure-Ruby / self-hosted
   path. If it fails (unserializable state, or load no faster than recompile), **shelve it**
   and bank the parallelism/timeout wins instead.
3. Timebox it. Per priority 2, if a faster-to-apply speedup (A1/A2) is still unbanked,
   that comes first; this spike runs when it's the best available next step.

> **Net intent of A:** turn a multi-minute, opaque, sequential run into a fast, parallel,
> instrumented run that emits a compact, spec-faithful, machine-readable diff — with
> per-spec compile cost driven down by A6 if the Marshal spike pays off.

---

## Workstream B — Categorized burndown workflow *(support activity)*

Per the operating method, burndown is what we do **when speedup work surfaces a bug**:
stash, find the relevant specs, make them green, resume. This tooling makes that cheap.
Built on A3's JSONL — a deterministic pipeline so Claude's tokens go to *fixing*, with
discovery and grouping done by scripts. It also serves the every-few-cycles
low-hanging-fruit pass (0.3).

### B1. Failure classifier (`tools/classify_failures.rb`)
Consume the JSONL and bucket every failure by **phase** then **normalized signature**:
- **COMPILE_FAIL** → parser/transform errors. Sub-key by error text
  (e.g. `ParseError@<construct>`, `undefined method 'pair'`). *Deterministic, highest priority.*
- **CRASH** → runtime segfault. Sub-key by nearest available locus (compile a crasher
  with `-g` once to recover a frame; otherwise key on last-emitted assertion).
- **FAIL** → ran, assertions failed. Sub-key by normalized expected/actual message.

Emit a **ranked table**: `signature → count → example specs`. One row that touches 12
specs is one fix worth 12 — this is the "group same-root-cause" the user asked for.

### B2. Parser-first ordering
Surface COMPILE_FAIL signatures first: they are reproducible without running anything,
they block whole files, and they're usually a single parser/transform defect. Burndown
order falls out of the classifier: **parser/compile → crash → assertion-fail**.

### B3. Auto-extracted minimal repro
The `create-minimal-test` / `investigate-spec` skills already exist. Have the classifier
emit the failing `it` block (or smallest construct for a compile error) as a ready-to-run
snippet, so Claude skips the token-expensive extraction step.

### B4. Regression diff (`tools/spec_diff.rb`)
Diff this run's JSONL against the previous: **newly-passing** and **newly-failing** only.
Claude reads the diff, not the full set — and it doubles as the commit-gate evidence.
`selftest` + `selftest-c` must stay green (existing rule) on every burndown commit.

### B5. The loop (what Claude runs unilaterally)
```
make spec-results               # A1–A3: parallel, JSONL (full baseline)
tools/classify_failures         # B1: ranked signatures, parser-first
# pick top signature → fix compiler (lib/core or compile_*.rb)
make spec-results SPECS=<glob>  # A5: scoped re-run of just that signature, fast
make spec-results               # A1: full run as commit gate
tools/spec_diff                 # B4: confirm net-positive, no regressions
# commit thematically
```
Each step is deterministic and cheap; Claude's judgement is spent only on the fix.

> Promote B as one plan (e.g. **SPECPIPE**) that delivers the three scripts and the
> `make spec-results` target together — they're useless apart.

---

## Workstream C — Code generator quality at the source (CODEGEN goal)

The compiler is self-hosted, so **better codegen also speeds up the spec loop** — it
compounds with Workstream A (a faster compiler compiling faster code).

**Framing correction — the peephole optimizer is a dead path, not a win path.** The
existing peephole pass is *papering over* low-quality generation: it only appears to help
because no effort has gone into emitting good code in the first place. Adding peephole
rules **entrenches** the bad codegen and is the wrong direction. The goal is to fix
generation **at the source** — `compile_*.rb` and the emitter — so the right
instructions are produced directly. As source generation improves, the peephole pass
should *shrink toward removal*, not grow. Treat "needed a new peephole rule" as a smell
pointing at the generator that produced the garbage.

`tools/asm_diff_counts.rb`, `asm_ngram.rb`, `compare_asm.rb` already exist — use them per
operating-method step 2 to *estimate* which generation defect wastes the most emitted
code, so the codegen candidates can be ranked against the measured A-items.

Candidate generation fixes (ranked fresh each iteration, not a fixed order):
- **Baseline metrics first (ASMBASE plan, already proposed)** — instruction counts per
  benchmark, so every change is measured. This is the prerequisite for the rest of C.
- **Stop emitting redundant moves / spills at the source** — e.g. `compile_*.rb` emitting
  `movl $X,%eax; movl %eax,%edx` or push/pop around values that could stay in a register.
  Fix the emission, don't add a cleanup rule.
- **Generate immediate-operand forms directly** (`cmpl $0,%edx`) instead of materializing
  a constant into a register first.
- **x86 scaled addressing** for array/field access (`(%base,%idx,4)`) instead of the
  manual shift+add+push/pop in `compiler.rb`.
- **Calling-convention fast path** — `compile_calls.rb` over-allocates `args.length+4`
  slots and spills every arg; emit a tight 0–2 arg path.
- **Register allocation** — `regalloc.rb` self-describes as "bare minimum"; the deepest
  fix and the one that removes the most spill/move garbage at the root. Highest effort.

> Gate every change on `selftest` + `selftest-c` + the ASMBASE metric. Each is its own
> thematic commit. A real win shows up as *less generated code*, ideally with peephole
> hits *dropping* — if the only thing that improved is peephole catching more, the
> source fix is still missing.

---

## Workstream D — Pure Ruby & dropping the C GC (PURERB goal)

All enabling infrastructure exists: the `%s(...)` parser, and `__alloc/__realloc/__array`
wrappers in `lib/core/base.rb`.
1. **GCAUDIT plan (already proposed)** first — document *why* the GC is disabled
   (leaks today), the allocation taxonomy, and the precise API surface to reimplement.
2. **Reimplement mark/sweep in s-expressions**, swapping `calloc/realloc` for direct
   `brk`/`mmap` syscalls; delete `tgc.c` and its link step. Target a simpler tracking
   structure (linked list + mark bitmap) than the C hash table.
3. **Longer horizon (note, don't scope now):** emit ELF directly to drop the `gas`/`ld`
   dependency entirely — fully realizes "pure Ruby" *and* removes the last toolchain
   step from the spec loop. Overlaps MULTIARCH; keep as a stated direction.

---

## Workstream E — Repo cleanup & restructuring

Phased, each phase gated by `selftest`/`selftest-c` green and committed separately.
The compiler is self-hosted, so file moves can break the build — **safe deletions first,
structural moves last and incrementally.**

**E1 — Zero-risk deletions (do now):** dead 2014–2016 emacs lock symlinks
(`.#charset.rb` etc.), `.gitignore~`, empty `.s`, `selftest_errors.tmp`, stray
`rubyspec_temp_*.rb` and `verify_all_*` artifacts in root. Commit the current dirty tree
(`CODEGEN-*.md` edit, LOCALDEV deletions, untracked `error-log.jsonl`).

**E2 — Move scratch out of root:** `debug_*.rb`, `bisect-parse-error.rb`,
`print_sexp.rb`, `debug_spec.sh` → `tools/debug/`. Tidy `~`/`#` backup files in
`mybin/`, `test/`, `examples/`, `features/`. Tighten `.gitignore`.

**E3 — Structural moves (careful, incremental):** consider `lib/scope/` for the 9 scope
classes and `lib/compiler/` for the core modules. **Only if** the self-host build's
include paths can absorb it — one move + full bootstrap per step, never a big-bang.
Low confidence this is worth the churn; may defer.

**E4 — docs hygiene:** archived plans carry many timestamped `spec.<ts>.md` snapshots.
Prune archived plans to final `spec.md` + `log.md`. De-duplicate LOCALDEV (present in
both active and archived). Optionally create the `docs/WORK_STATUS.md` that CLAUDE.md
already references.

---

## Workstream F — Tooling (continuous; a standing part of the loop)

Per priority 4 (token-efficiency), **every iteration should also ask "what tool would
make the next iterations cheaper?"** Reusable, deterministic tooling is how Claude spends
tokens fixing rather than rediscovering — and the loop itself generates the requirements.
This is not a one-off phase; it runs alongside everything.

Standing remit:
- **Spot tooling gaps from the work in flight.** When a step needs a manual,
  token-expensive, or repeated investigation, that is a signal to build a tool for it.
  (Examples already surfaced by this plan: the benchmark harness (0.1), failure
  classifier (B1), regression diff (B4), rewrite tracker (A4).)
- **Sharpen existing tools.** `tools/asm_diff_counts.rb`, `asm_ngram.rb`, `compare_asm.rb`
  already exist — extend them where step 2 estimation needs better proxies; wire their
  output into the candidate ranking rather than reading it by hand.
- **Prefer deterministic scripts over agent reasoning** for anything mechanical:
  extracting a minimal repro, splitting/merging spec lists across the local+remote
  runners, normalizing error signatures, producing the per-iteration ranking table.
- **Keep tools discoverable and reused.** One home (`tools/`), no duplicates, documented
  in their header — so later iterations and future sessions find them instead of
  rebuilding them.

Treat new tooling like any other candidate: a tool earns its slot when it will save more
effort across upcoming iterations than it costs to build. Small, composable, committed.

---

## Candidate backlog (the loop re-ranks this every iteration)

This is **not** an execution order — it's the pool the operating-method loop draws from.
Only two things are fixed: **E1** (clean tree) and **Workstream 0** (benchmark) come
first, because without a clean baseline and real numbers every later choice is blind.
After that, each iteration re-ranks the rest by payoff ÷ effort against the latest
benchmark + estimates.

**Fixed prerequisites**
- **E1** — clean working tree, commit a known-good baseline.
- **Workstream 0** — per-stage timing + fixed benchmark set. Ends the speculation; every
  later ranking depends on it.

**Candidate pool** (rank fresh each iteration; *typical* effort/category in brackets)
| Candidate | What it buys | Measured or estimated? |
|---|---|---|
| A2 fast timeouts | kills ~24 min/run crash waste | measured (cheap) |
| A1 parallel + remote | ~10–14× wall-clock on the idle box | measured (cheap-ish) |
| A3 harness JSONL + A5 scoped runs | unblocks B; fast inner loop | enabling (cheap) |
| A6 Marshal precompile | removes ~80× `lib/core` recompile — possibly the biggest win | **spike to estimate** |
| A4 rewrite burndown | correctness + cuts upstream divergence | measured-ish |
| C codegen *at the source* (kill redundant moves/spills, immediate operands, scaled addressing, call fast-path, regalloc) | faster binaries **and** a faster self-hosted compiler → faster spec runs. *Not* more peephole rules — fix generation, shrink the peephole pass | **estimate via `tools/asm_*`** |
| D2 pure-Ruby GC | PURERB goal; unblocks running GC-on | estimate |
| D3 direct ELF | drops `gas`/`ld` from the loop entirely | large spike |
| E2–E4 cleanup | maintainability | known/cheap |
| F tooling | makes every future iteration cheaper | continuous — evaluate each iteration |

The codegen row is the clearest case of step 2: we can't benchmark a generation fix we
haven't written, but `tools/asm_diff_counts.rb` / `asm_ngram.rb` can *estimate* how much
emitted code the wasteful pattern occupies — enough to rank a source-level fix against the
measured A-items.

## Proposed new plans to file

| Code | Covers | Goal |
|---|---|---|
| **SPECBENCH** | Workstream 0: per-stage timing, fixed benchmark set, low-hanging-fruit harness | COMPLANG (foundational) |
| **SPECFAST** | A1–A3, A5: parallel/remote runner, fast timeouts, harness-layer JSONL, scoped runs | COMPLANG |
| **COREMARSHAL** | A6 spike: Marshal the compiler symbol-state to skip per-spec `lib/core` recompile (built-in Marshal to test, `pure_ruby_marshal` to adopt) | COMPLANG / PURERB |
| **SPECPURE** | A4: enumerate & burn down the `run_rubyspec` rewrites; drive divergence → 0 | COMPLANG / mspec-migration |
| **SPECPIPE** | B1–B5: classifier, diff, `make spec-results`, burndown loop | COMPLANG |
| **REPOCLEAN** | E1–E4: deletions, scratch relocation, docs pruning | (housekeeping) |
| **TOOLING** | Workstream F: standing remit to spot tooling gaps and build/sharpen reusable tools | (continuous) |

ASMBASE and GCAUDIT already exist and slot into C and D above. **PEEPFIX (add peephole
rules) should be reconsidered** — per the Workstream C framing it pushes the dead path;
its underlying cases are better fixed at the generator. Keep it only as a record of which
garbage patterns the source fixes must eliminate.

---

*Status: PROPOSAL — awaiting review. Promote accepted workstreams into individual plans.*
