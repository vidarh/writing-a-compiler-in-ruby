# Spec-Speedup Workflow

*The durable entry point for this line of work. If a session is restarted, **read this
first, then `docs/NEXT_STEPS.md`** (the candidate backlog and detail). This document is
the standing operating procedure; NEXT_STEPS is the menu it draws from.*

Created 2026-06-26.

## Mission

**Make rubyspec runs fast.** Spec-run speed is the top priority and the goal in its own
right — a fast loop is what makes every other improvement affordable. Everything else
(burndown, codegen, GC, cleanup) is pursued in service of, or interleaved with, that.

## The loop (continuous — never a fixed one-at-a-time order)

Re-rank *all* candidates every iteration and take the best payoff/effort available now:

1. **Benchmark.** Run the measurement harness: per-stage timings (parse → transform →
   codegen → `gas` → `ld` → run) over a fixed, committed spec set. Hard numbers for
   everything measurable. *(If the harness doesn't exist yet, building it is the first
   task — without it we optimize blind.)*
2. **Estimate the un-benchmarkable.** Some potential can't be measured until built —
   mostly codegen. Guess its payoff from cheap proxies (`tools/asm_diff_counts.rb`,
   `asm_ngram.rb`: how much emitted code a pattern wastes). A rough estimate is enough to
   rank; we're choosing what to *try*.
3. **Pick low-hanging fruit first.** Rank the whole pool — measured + estimated, across
   every workstream — by payoff ÷ effort. Take the cheapest effective win. Big-ticket
   items (e.g. the Marshal precompile) get a slot only when a quick **spike** says the
   payoff justifies the cost *and* nothing cheaper remains.
4. **Iterate, including re-benchmarking.** Apply the win, re-run the benchmark (the
   bottleneck moves), re-estimate, re-rank. Expect the ranking to churn — that's the point.

## Interleaved burndown (not a separate phase)

Speedup work surfaces compiler bugs (faster/changed paths expose them). When it does:
1. `git stash` the speedup work.
2. **Identify the relevant specs** (failure-classifier tooling) and **make them green** by
   fixing the compiler.
3. If it still blocks: write a **separate minimal test** (`create-minimal-test` skill) or
   **simplify the offending code**, then resume the stashed work.

Every few iterations, run *different* parts of rubyspec as benchmarks and scan for
**low-hanging fruit** — cheap speed *or* correctness wins — which also keeps the benchmark
set representative as coverage grows.

## Standing rules

- **Codegen: fix generation at the source, not the peephole pass.** The peephole optimizer
  is a *dead path* — it only helps because generation is poor, and adding rules entrenches
  the problem. Fix `compile_*.rb` / the emitter so the right instructions are emitted
  directly; the peephole pass should shrink toward removal. "Needed a new peephole rule" is
  a smell pointing at the generator. A real win = *less generated code*, ideally with
  peephole hits dropping.
- **Tooling is continuous.** Each iteration, ask "what tool makes the next iterations
  cheaper?" Push mechanical work into deterministic, reusable scripts under `tools/` (one
  home, no duplicates, documented headers) so tokens go to fixing, not rediscovering.
- **Pure Ruby only** (`%s(...)` s-expressions). The C GC (`tgc.c`) is a tolerated
  exception we aim to delete. No new C.
- **Minimise rubyspec divergence.** The end goal is running unmodified upstream `ruby/spec`
  under real mspec. Today's runner rewrites spec files (sed) and uses a custom
  `rubyspec_helper.rb` shim — *not* mspec. New tooling (incl. machine-readable output) must
  live in the **harness layer, never in the spec files**, and should *reduce* the sed
  rewrites, not add to them. Each rewrite is a compiler bug to burn down.
- **Spike before committing to expensive work.** Verify complexity/payoff cheaply first;
  shelve a candidate the moment a faster-to-apply alternative appears.
- **Gate every change** on `selftest` + `selftest-c` green (plus the asm metric for
  codegen). Thematic commits, feature branches for non-trivial work.

## Where the detail lives

- `docs/NEXT_STEPS.md` — full candidate backlog (Workstreams 0/A–F), proposed plans
  (SPECBENCH, SPECFAST, COREMARSHAL, SPECPURE, SPECPIPE, REPOCLEAN, TOOLING), and the
  verified vs. estimated facts table.
- `docs/goals/` — CODEGEN, COMPLANG, SELFHOST, PURERB, etc.
- `tools/` — existing asm metric scripts; new burndown/benchmark tooling lands here.
- `https://github.com/vidarh/pure_ruby_marshal` — starting point for serializing compiler
  state (the Marshal precompile spike).

## On restart — first actions

1. Read this file, then `docs/NEXT_STEPS.md`.
2. Ensure a clean tree (commit/stash), `selftest` + `selftest-c` green.
3. If no benchmark harness exists yet, build it (Workstream 0 / SPECBENCH). Otherwise run
   it and start the loop at step 1.
