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
- `make selftest` shows `Fails: 3` — **pre-existing on the current tree, not introduced
  here** (proven by the zero compiler-source-change diff). Flagged separately; it
  contradicts the earlier audit's "selftest all passing" note and is worth its own look,
  but is out of scope for SPECBENCH. `selftest-c` not re-run: with no compiler-source
  changes it cannot be affected.

*Status: IMPLEMENTED*
