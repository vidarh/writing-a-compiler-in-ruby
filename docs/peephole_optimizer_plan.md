# Peephole optimizer improvement plan

## Goals
- Keep the peephole pass small and predictable while making it easier to extend safely.
- Bias toward rules that are obviously correct for the compiler’s codegen patterns and cheap to evaluate.
- Make every change measurable: instruction deltas and test outcomes (selftest, selftest-c) drive decisions.

## Current state (from review)
- Rules are hard-coded in `peephole.rb` with implicit window state; safety relies on comments (“@unsafe”) instead of checks.
- No normalization step, so equivalent sequences may miss rewrites; register/memory operand kinds are not differentiated.
- There is no built-in way to see which rules fired or to quantify wins besides manual diffs of `.s` outputs.
- Generated asm (e.g. `out/selftest.s`) shows lots of short, repetitive sequences (push/pop of scratch regs, mov-to-eax chains, adjacent stack adjusts) that are good peephole targets.

## Refactor / maintainability plan
- Introduce a tiny Rule struct: `pattern`, optional `guard` (predicate on matched ops), and `rewrite` block. Keep the window small (<=3 instructions) to avoid complexity.
- Normalize operands before matching (register aliases, literal 0 vs `$0`, canonicalizing `mov` direction where safe) so rules match consistently.
- Tag operands as reg/mem/imm in the in-memory representation so rules can quickly reject unsafe mem-to-mem rewrites.
- Add a cheap liveness hint per window: track which scratch regs (`%eax`, `%ebx`) are killed/used in the window to let rules like mov-chain folding prove safety instead of relying on comments.
- Add tracing hooks (env flag) to log which rules fire and how many times; keep disabled by default to avoid slowing the compile.
- Strengthen tests: fixture-based sequence → expected rewrite tests (already started in `test/test_peephole_fixture.rb`), plus golden-file checks that the optimizer leaves already-optimized sequences unchanged.
- Keep the peephole interface stable: `emit`/`flush` stay the same so the emitter does not need to change while we reshape internals.

## Quick wins to prototype (low risk)
- Add a tiny “safety layer” before new rewrites: classify operands (reg/mem/imm), mark obvious stack-affecting ops, and expose `scratch_dead?(:eax, window)` to require proof that `%eax` is killed after a rewrite.
- Once the guard exists, gate the following high-frequency patterns:
  - `movl imm, %eax; cmpl %eax, reg` → `cmpl imm, reg` only if `%eax` is dead.
  - `movl mem, %eax; movl %eax, reg` → `movl mem, reg` only if `%eax` is dead and `reg` is a register (avoid mem→mem).
  - Push/pop identical reg removal already exists; keep it strict. No push→pop to mov without reg-stability proof.
- Keep stack adjustments out of scope until a trusted stack-effect model exists (past attempts caused crashes).
- Prefer changes that reduce instruction count in measured outputs (`selftest.s`, `selftest2.s`) and keep both `make selftest` and `make selftest-c` green.

## Collecting asm samples and measuring impact
- Baseline outputs: keep copies of `out/selftest.s` and a small grab-bag of `.s` files (e.g. `out/driver.s`, a few rubyspec snippets) under `/tmp/peephole-baselines/` before each experiment.
- Diff mechanics:
  - `ruby tools/compare_asm.rb old.s new.s` to find first structural change.
  - `ruby tools/asm_diff_counts.rb old.s new.s` to see opcode count deltas and total instruction change.
  - `wc -l out/*.s` to watch overall size drift.
- Pattern mining: `ruby tools/asm_ngram.rb out/selftest.s --n 2 --limit 40` to surface the most common short sequences worth targeting next.
- Always run `make selftest` and `make selftest-c`; only keep a rule if it passes both and the count diffs show a net improvement or a clear simplification.
