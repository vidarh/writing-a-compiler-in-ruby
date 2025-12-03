# Peephole Refactor Steps (Staged, Low-Risk)

Goal: introduce a maintainable, data-driven peephole pass without regressing today’s output. Each step is individually testable and leaves the existing optimizer intact until explicitly switched.

## Stage 0: Stabilize Baseline
- Keep current `peephole.rb` as-is; add a flag to opt into any new pass (env var or emitter opt-in) but default to off.
- Capture a baseline fixture: `ruby -I. ./driver.rb test/selftest.rb -I. -g > out/baseline_selftest.s` for regression checks.

## Stage 1: Shared Instruction Model (Side-by-Side)
- Add a new `peephole2.rb` (not wired yet) with:
  - `Instruction` struct (op, args) with helpers: `imm?`, `reg?`, `mem?`, `same_regs?`, `uses_esp?`.
  - `Rule` objects with `pattern`, `guard`, `rewrite`.
  - A pure function `apply_rules(buffer)` that rewrites an array of instructions; no I/O.
- Add unit-style fixtures under `test/peephole/` with “input asm” -> “expected asm” to prove matching and guard behavior.

## Stage 2: Minimal Safe Rule Set (Opt-In)
- Implement only the safest, high-value rules:
  - Drop `movl r, r`.
  - Drop `subl $0, reg` / `addl $0, reg`.
  - Combine adjacent `addl`/`subl` on same dest when both are immediates and no `%esp` touch between them.
  - Remove exact `pushl r` / `popl r` pairs when no instructions in between (or only comments).
- Gate the new pass behind an env flag (e.g., `PEEPHOLE2=1`), leaving the legacy pass untouched otherwise.

## Stage 3: Instrumentation and Diffing
- Add counters per rule, emitted to stderr when a debug flag is on.
- Add a small diff script to compare `out/baseline_selftest.s` vs. `out/selftest.s` by instruction count and rule hits. Fail CI if instruction count grows unexpectedly.

## Stage 4: Expand with Data-Backed Rules
- Use `tools/asm_ngram.rb` (already added) to rank frequent n-grams in `out/*.s`; add one rule at a time starting from top offenders.
- For each added rule, add a fixture and record before/after hit counts on selftest.

## Stage 5: Switch-Over (Optional)
- Once rule set is stable, wire `peephole2` as the default and keep the legacy pass under a fallback flag (`PEEPHOLE_LEGACY=1`).
- Keep instrumentation to guard against regressions as new code is added.

## Testing Protocol
- Fast: unit fixtures in `test/peephole/`.
- Integration: `ruby -I. ./driver.rb test/selftest.rb -I. -g` and compare against baseline hashes; optional `make selftest` when Docker is available.
- Block any rule that increases instruction count or changes codegen shape without explicit sign-off.
