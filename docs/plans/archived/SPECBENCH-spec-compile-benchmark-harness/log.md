# SPECBENCH — Execution Log

## 2026-06-26 — Implemented

Built the benchmark harness and captured the initial baseline.

### Delivered
- `tools/bench_compile.rb` — instrumented mirror of `driver.rb`; times parse / transform /
  codegen, emits `BENCH_TIMING {json}` to STDERR, writes identical `.s` to STDOUT (verified
  byte-identical to `driver.rb` output on the tiny input).
- `tools/specbench.rb` — orchestrator over the fixed set; per item samples the compile
  REPS times (default 3, `SPECBENCH_REPS`) keeping the per-stage **min**, links twice
  keeping the warm (min) link time, and times the run. Writes `docs/specbench.jsonl` +
  `docs/specbench_baseline.txt`, plus the lib/core floor-fraction analysis.
- `tools/bench/tiny.rb` — one-statement fixture isolating the lib/core floor.
- `make specbench` target.
- `docs/specbench.jsonl` + `docs/specbench_baseline.txt` — committed baseline.

### Key findings (the point of Workstream 0)
- **The compiler dominates; the toolchain does not.** Driver compile = 5–12 s vs link
  < 0.5 s vs run < 0.1 s. Refutes any need to optimize `gas`/`ld`.
- **codegen is the single largest stage** (~5 s on selftest), then parse (~4–5 s);
  transform is small (~2 s).
- **lib/core floor ≈ 5 s / 152,264 asm lines, paid on EVERY compile** (parser.rb
  auto-requires `core/core.rb`) — 32–47 % of a real compile's time. Makes the
  COREMARSHAL (Marshal-precompile) spike evidence-backed: it targets the single largest
  removable fixed cost.

### Methodology notes / caveats
- The single `gcc` invocation does assemble+link in one step, so `gas`/`ld` are reported
  as one "link" stage (documented in the tool + baseline header).
- Absolute numbers are load-sensitive; this baseline was captured on a machine under
  concurrent load, so absolutes run high. The **relative** breakdown (the decision-relevant
  signal) is stable across runs. Re-run on an idle machine for cleaner absolutes — that is
  also what the idle-box plan (SPECFAST) provides.

### Verification
- `tools/bench_compile.rb` output verified byte-identical to `driver.rb`.
- No compiler-source (`*.rb`) files changed (only `tools/`, `Makefile` target, `docs/`),
  confirmed via `git diff --stat master`. So compile behavior is unchanged by definition.
- Gate: `make selftest` → `Fails: 0` (verified across 3 consecutive runs) and
  `make selftest-c` → `Fails: 0` (exit 0). Both green.
  - One earlier `make selftest` invocation reported `Fails: 3`; it could not be
    reproduced and I have **no verified explanation** for it. (An earlier version of this
    log speculated it was "pre-existing under load" — that was unfounded and has been
    removed. Do not invent causes for gate failures.)

## 2026-06-26 — Correction: this measures proxies, NOT real specs

This first cut benchmarks `tiny.rb` / `selftest.rb` / `driver.rb` — the **compiler
pipeline on proxy inputs**. It does **not** run any rubyspec, so it omits what actually
dominates the real spec loop: the `run_rubyspec` preprocessing, the `rubyspec_helper` mock
framework, the spec body, and above all the **run stage** with real pass/fail/**crash/
timeout** outcomes (30 s timeouts are where the real suite burns wall-clock). The
`lib/core` floor number is real and useful, but it is a proxy, and this harness was
mislabeled as a "spec" benchmark.

**Superseded by a real-spec, PHASE-BY-PHASE benchmark — now delivered:**
`tools/specbench_rubyspec.rb` (`make specbench-rubyspec`) benchmarks a fixed set of actual
`rubyspec/language/*` files and measures **every phase directly** —
preprocess → parse → transform → codegen → link → run — plus the outcome
(PASS/FAIL/CRASH/COMPILE_FAIL/TIMEOUT). It uses an opt-in `SPEC_PREPROCESS_ONLY` seam added
to `run_rubyspec` (default behaviour unchanged; verified). `specbench`/`bench_compile` are
retained as the compiler-pipeline microbenchmark (floor + self-host timing).

First phase-by-phase baseline (ax52, uncontended; outcomes match `docs/rubyspec_language.txt`):

    spec        outcome    prepro parse transf codegen link  run  total
    and_spec    PASS         0.19  0.84  0.32   0.70   0.08 0.00  2.21
    if_spec     FAIL         0.98  0.87  0.34   0.74   0.08 0.00  3.11
    ensure_spec FAIL         0.81  0.87  0.33   0.72   0.07 0.00  2.87
    array_spec  CRASH        0.38  0.87  0.34   0.72   0.08 1.06  3.53
    module_spec COMPILE_FAIL 0.24   -     -      -      -    -    2.13

Findings:
- **compile (parse+transform+codegen) ≈ 1.85 s, constant across specs** — the lib/core
  floor, ~60–85% of total. Confirms the lib/core precompile (COREMARSHAL) as the top lead.
- **preprocess is a real, size-dependent phase (0.2–1.0 s)** — the sed-based rewriting in
  `run_rubyspec` is surprisingly costly for large specs (`if_spec`: 0.98 s ≈ 1/3 of total).
  A *second* speedup lead that also serves divergence reduction (fewer rewrites = faster).
- **link is negligible (0.08 s); run ≈ 0** for pass/fail; the crasher costs ~1 s.
- Gap: this set has no *hanging* spec, so the 30 s-timeout cost is not yet represented — add one.

*Status: IMPLEMENTED — compiler-pipeline microbenchmark and the real phase-by-phase
benchmark both delivered.*
