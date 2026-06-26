SPECBENCH
Created: 2026-06-26 16:09

# Spec-Compile Benchmark Harness (per-stage timing + fixed set)

[COMPLANG] Build the measurement foundation for the spec-speedup work: per-stage timing
(parse → transform → codegen → link → run) over a fixed, committed benchmark set, so every
later speedup is ranked on real numbers instead of speculation.

## Goal Reference

[COMPLANG](../../goals/COMPLANG-compiler-advancement.md): spec-run speed is the current
top-priority lever on completing the compiler (see
[`docs/COMPILER_WORKFLOW.md`](../../COMPILER_WORKFLOW.md) and
[`docs/NEXT_STEPS.md`](../../NEXT_STEPS.md) Workstream 0). The workflow's loop *starts* with
"benchmark", and there is currently **no benchmark** — so this is the gating first step.

## Prior Plans

- **[ASMBASE](../ASMBASE-add-assembly-metrics-baseline/spec.md)** (PROPOSAL): measures
  *static* assembly quality (instruction counts / n-grams of `out/selftest.s`). SPECBENCH
  is complementary and orthogonal: it measures *wall-clock time per pipeline stage*, not
  output size. ASMBASE answers "is the generated code smaller?"; SPECBENCH answers "where
  does spec-compile time actually go, and did this change make it faster?". They share the
  `tools/` + `docs/*baseline*` pattern but neither depends on the other.
- No prior or archived plan measures pipeline timing.

## Root Cause

Every claim driving the spec-speedup work ("the compiler dominates the loop", "`lib/core`
recompilation is the bottleneck", "`gas`/`ld` are cheap") is **estimated, never measured** —
there is no per-stage timing anywhere. A quick check this session already shows a trivial
one-line program (`puts "hello"`) takes **3.73 s** to compile and emits **152,264 lines**
of assembly — essentially all of it `lib/core`, paid again on every spec. That is a strong
signal, but it is one ad-hoc data point with no committed baseline and no breakdown of
parse vs. transform vs. codegen. Without a repeatable harness we cannot rank candidate
speedups or detect regressions.

## Infrastructure Cost

Low. Two new tools under `tools/` (no changes to the compiler sources, so no self-host
risk), one fixed tiny input, one `make` target, and committed baseline files in `docs/`
(mirroring `docs/rubyspec_*.txt` / `docs/asm_baseline.txt`). Runs under MRI with the local
i386 toolchain already present (no Docker).

## Scope

**In scope:**

1. **`tools/bench_compile.rb`** — a thin instrumented mirror of `driver.rb` that times the
   three in-process stages (parse, transform/`preprocess`, codegen/`compile`) and emits a
   one-line JSON timing record to STDERR while writing the `.s` to STDOUT exactly like
   `driver.rb`. Used by the harness; also usable standalone.
2. **`tools/specbench.rb`** — orchestrator over a **fixed benchmark set** that, per item,
   measures: parse / transform / codegen (via `bench_compile.rb`), **link** (the real
   `gcc` assemble+link, mirroring `./compile`), and **run** (timed execution, where
   meaningful). Emits `docs/specbench.jsonl` (machine-readable) and `docs/specbench_baseline.txt`
   (human summary), and reports the **`lib/core` floor** (tiny-program compile time) plus
   what fraction of each larger build that floor represents — the headline low-hanging-fruit
   signal.
3. **Fixed benchmark set:** `tools/bench/tiny.rb` (one statement — isolates the `lib/core`
   floor), `test/selftest.rb` (medium, the canonical self-host test), and `driver.rb`
   (large, the compiler compiling itself). Small, stable, representative of the size range.
4. **`make specbench`** target that runs the harness and writes the baseline files.
5. **Commit the initial baseline.**

**Out of scope:**
- Separating `gas` from `ld` — the toolchain runs them as one `gcc` invocation; reported as
  a single "link" stage (documented).
- Acting on the findings (parallel runner, Marshal precompile, etc. — separate plans).
- The full low-hanging-fruit scanner over rubyspec output (ties to the SPECPIPE classifier;
  this plan delivers only the floor-fraction signal).
- Any change to compiler sources, `driver.rb`, or `compile`.

## Expected Payoff

- **Ends the speculation:** real per-stage numbers replace every ≈ estimate in NEXT_STEPS.
- **Confirms or refutes the `lib/core`-floor hypothesis** with a committed number and makes
  the Marshal-precompile spike (COREMARSHAL) decidable on evidence.
- **Regression/▲improvement detector:** `make specbench` after any change shows the delta,
  the way `make asm-compare` does for code size.
- **Ranking input:** gives the operating-method loop the measured side of its payoff/effort
  ranking.

## Proposed Approach

1. Create `tools/bench/tiny.rb` and `tools/bench_compile.rb` (mirror `driver.rb`, wrap each
   stage in `Time.now` deltas, JSON to STDERR).
2. Create `tools/specbench.rb`: ensure `out/tgc.o`, loop the fixed set, time driver-stages +
   link + run, write `docs/specbench.jsonl` and `docs/specbench_baseline.txt`.
3. Add `make specbench`.
4. Run it, sanity-check the numbers, commit tools + baseline.

## Acceptance Criteria

- `make specbench` runs clean and (re)writes both `docs/specbench.jsonl` and
  `docs/specbench_baseline.txt`.
- The summary reports, per benchmark item, time for parse / transform / codegen / link / run
  and a total, plus the `lib/core` floor and its fraction of the larger builds.
- `selftest` + `selftest-c` still pass (no compiler-source changes, so this is a sanity gate).
- Baseline files committed.

*Status: IMPLEMENTED — see log.md. Harness + baseline delivered; key finding: compiler
dominates the loop (link/run negligible), codegen is the largest stage, lib/core floor is
32–47% of every compile.*
