# Compiler Completion Workflow

*The durable entry point for this line of work. On restart, **read this first, then
`docs/NEXT_STEPS.md`** (the candidate backlog and detail). This is the standing operating
procedure; NEXT_STEPS is the menu it draws from.*

Created 2026-06-26.

## Mission

**Complete the compiler.** The goal is a correct, self-hosting Ruby compiler:

- **Correct** — passes the Ruby spec suite, ideally **unmodified upstream `ruby/spec`**
  under real mspec (today we run a custom shim with sed-rewritten specs; that divergence
  is itself debt to burn down).
- **Self-hosting cleanly** — a clean three-stage bootstrap (MRI → c1 → c2 → c3, c2≡c3)
  with **zero `@bug`/FIXME workarounds** in the source (SELFHOST goal).
- **Pure Ruby** — using the `%s(...)` s-expression extension; the C GC (`tgc.c`) is a
  tolerated exception we aim to **delete and replace in-language** (PURERB goal).
- **Decent code** — the generator emits reasonable machine code (CODEGEN goal), with a
  path to other architectures (PARSARCH/MULTIARCH).

Everything else — including making spec runs fast — is **instrumental to that mission**,
not a goal in itself.

## Why spec-run speed is the current top priority (but only a facet)

Completing the compiler means a long burndown of correctness/feature/semantics work, each
fix validated by recompiling and re-running specs. **That validation loop is the binding
constraint right now**: a one-line program takes ~5 s to compile (essentially all
`lib/core`, recompiled every time), the runner is sequential with 30 s timeouts, and
output is unstructured. While the loop is this slow and opaque, every correctness fix is
expensive, so the fastest route to a *complete* compiler currently runs **through** a
faster, measurable loop.

So speed is prioritized **because it is the lever on completion**, not because it is the
point. As the loop gets fast and cheap, the balance of work shifts back toward direct
correctness/feature/semantics/GC/codegen work — that is the expected, healthy drift.

## THE GATE — non-negotiable, checked before every commit

**Every change must be gated by BOTH `make selftest` AND `make selftest-c` passing with
ZERO failures.** No commit, no "done", no moving on until both are clean.

- **`make selftest-c` is the survival gate.** It compiles the compiler with the
  *self-compiled* compiler and runs the self-test. If it fails, **the compiler is broken**
  — it can no longer correctly compile itself, self-hosting is lost, and **all further
  progress is blocked.** A `selftest-c` failure is a full stop: drop everything and fix it
  before any other work. Nothing else matters while it is red.
- **`make selftest` (under MRI)** must also be green — it catches regressions before they
  reach the self-host stage.
- **Zero failures means zero.** Not "pre-existing", not "unrelated", not "my change didn't
  touch that". If the gate is red, the tree is not in a committable state — investigate the
  actual cause before proceeding. Never commit on a red result, and never invent an
  explanation ("flaky", "load") to dismiss a failure: find the real reason.
- Codegen changes additionally gate on the asm metric (`make asm-stats`/`specbench`).

This gate is the reason the compiler can keep evolving at all. Treat it as inviolable.

## The loop (continuous — re-rank every iteration)

Each iteration picks the **highest-leverage step toward completion** available now —
across *all* facets (correctness burndown, loop speed, codegen, GC removal, divergence,
tooling, cleanup), not one fixed track:

1. **Benchmark / measure.** Run `make specbench-rubyspec` — the **real** benchmark: actual
   `rubyspec/language/*` files end-to-end via `run_rubyspec`, recording per-stage time
   **and outcome** (pass/fail/crash/compile-fail/timeout). (`make specbench` is a secondary
   compiler-pipeline microbenchmark on proxy inputs — the lib/core "floor", not specs.)
   **Run on ax52** for clean numbers. First baseline: compile (lib/core) is ~1.9 s and
   constant — 60–85% of each spec's total — so precompiling lib/core is the top speedup lead.
2. **Estimate the un-benchmarkable.** Some payoff can't be measured until built (most
   codegen; the size of a correctness cluster before you fix it). Estimate from cheap
   proxies (`tools/asm_*` for wasted code; failure-signature counts for how many specs one
   fix clears). Rough is enough — we're choosing what to *try*.
3. **Pick the highest-leverage step.** Rank the whole pool by payoff ÷ effort, where
   "payoff" is *progress toward completion* — specs turned green, `@bug`s removed, loop
   time cut, divergence reduced. Right now loop-speed wins often because it multiplies the
   value of every later correctness fix; take the cheapest effective one. Big-ticket items
   (e.g. Marshal precompile) earn a slot only when a quick **spike** says the payoff
   justifies the cost and nothing cheaper remains.
4. **Iterate, re-measuring.** Apply it, re-run the harness and specs (both the bottleneck
   and the failure profile move), re-estimate, re-rank. Expect churn — that's the point.

## Correctness burndown (a first-class facet, not just a side-effect)

Turning specs green *is* completing the compiler; speed just makes it cheap. Burndown
happens both **proactively** (pick a high-count failure signature and fix its root cause —
parser-first, since compile-failures block whole files) and **reactively** (when a speedup
surfaces a bug: `git stash`, fix the relevant specs, resume). When a fix is non-obvious,
write a **separate minimal test** (`create-minimal-test`) or **simplify the offending
code**. Group same-root-cause failures so one fix clears many. Every few iterations, run
*different* parts of rubyspec to find low-hanging fruit and keep coverage representative.

## Standing rules

- **Codegen: fix generation at the source, not the peephole pass.** The peephole optimizer
  is a *dead path* — it only helps because generation is poor, and adding rules entrenches
  the problem. Fix `compile_*.rb` / the emitter so the right instructions are emitted
  directly; the peephole pass should shrink toward removal. A real win = *less generated
  code*.
- **Tooling is continuous.** Each iteration, ask "what tool makes the next iterations
  cheaper?" Push mechanical work into deterministic, reusable scripts under `tools/` (one
  home, no duplicates, documented headers) so tokens go to fixing, not rediscovering.
- **Pure Ruby only** (`%s(...)` s-expressions). The C GC (`tgc.c`) is a tolerated
  exception we aim to delete. No new C.
- **Minimise rubyspec divergence.** End goal: unmodified upstream `ruby/spec` under real
  mspec. The runner currently sed-rewrites specs and uses a custom `rubyspec_helper.rb`
  shim (not mspec). New tooling (incl. machine-readable output) lives in the **harness
  layer, never in the spec files**, and should *reduce* the sed rewrites. Each rewrite is a
  compiler bug to burn down. Never edit `rubyspec/`.
- **Spike before committing to expensive work.** Verify complexity/payoff cheaply first;
  shelve a candidate the moment a faster-to-apply alternative appears.
- **Gate every change** on `selftest` + `selftest-c` green (plus the asm metric for
  codegen). Thematic commits, feature branches for non-trivial work.

## Progress metrics (how we know we're approaching "complete")

- **rubyspec pass rate** — files and individual examples (baseline: ~4% files, ~27%
  examples on language specs).
- **`@bug`/FIXME count** in the compiler source → 0 (SELFHOST).
- **Clean three-stage bootstrap** holds (c2 ≡ c3).
- **C GC removed**, GC running in-language (PURERB).
- **Active sed rewrites** in `run_rubyspec` → 0 (divergence).
- **Loop time** (`make specbench`) — the enabler metric, not the goal.

## Where the detail lives

- `docs/NEXT_STEPS.md` — candidate backlog (Workstreams 0/A–F), proposed plans, the
  verified-vs-estimated facts table.
- `docs/goals/` — COMPLANG, SELFHOST, PURERB, CODEGEN, PARSARCH, MULTIARCH (the mission's
  facets).
- `docs/KNOWN_ISSUES.md`, `docs/TODO.md` — outstanding correctness work.
- `tools/` — `specbench` (loop timing), `asm_*` (codegen estimation); new tooling lands here.
- `https://github.com/vidarh/pure_ruby_marshal` — starting point for the Marshal
  precompile spike (serializing compiler state to skip per-spec `lib/core` recompile).
- **Build machine `ssh compiler@ax52` — intended PREFERRED place to run things** (verified:
  16 cores, x86_64, ~125 GB RAM, no competing processes → cleaner/faster than the contended
  local box). **NOT yet provisioned** (verified 2026-06-26: bare machine — no `ruby`, no
  `gcc`, empty home, no repo). Before it can run the gate/benchmarks/specs it needs:
  `ruby` (MRI), `gcc` + 32-bit multilib, a repo clone, and `toolchain/32root` (rsync from
  local, or `bin/setup-i386-toolchain`). Until provisioned, run locally. Once set up it is
  the default runner and the host for the parallel/remote runner (NEXT_STEPS A1, ~32 cores
  with local). **Provisioning ax52 is itself a high-value early task.**

## On restart — first actions

1. Read this file, then `docs/NEXT_STEPS.md`.
2. Ensure a clean tree (commit/stash), `selftest` + `selftest-c` green.
3. Measure: `make specbench` (loop) and current spec status. Then enter the loop at step 1,
   choosing the highest-leverage step toward **completing the compiler**.
