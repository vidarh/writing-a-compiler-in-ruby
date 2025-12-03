# Peephole Optimizer Improvement Plan

## Current Notes
- The optimizer buffers raw instruction arrays and rewrites them with ad-hoc conditionals; pattern intent and safety assumptions are implicit.
- No canonical instruction model (op, operands, flags), so every pattern manually re-checks operand shapes and register scratch rules.
- No tests or stats, making it hard to add rules without regressions or a sense of payoff.
- Sample output shows heavy repetition and avoidable moves, e.g. loading a constant into `%eax` only to store it (`out/rubyspec_temp_alias_spec.s:1200`) and temporary register shuffling around stack slots (`out/rubyspec_temp_alias_spec.s:1056`).

## Make It Maintainable / Extensible
1) Normalized instruction model  
   - Introduce a tiny `Instruction` struct with `op`, `args`, and metadata (source, clobbers, flags). Normalize immediates, registers, and memory references up front in the emitter before they hit peephole.
2) Data-driven rewrite table  
   - Define patterns as data (array/DSL) with captures and predicates, e.g. `movl imm, %r; movl %r, mem -> movl imm, mem`. Keep guards for scratch-register assumptions explicit. Store rules in one place with tags (`stack_adj`, `move_fold`, `unsafe`).
3) Ordered micro-passes  
   - Run a deterministic pipeline by category (cleanup -> stack math -> move folding -> register shuffles). Allow different window sizes (2–4 instructions) without nesting conditionals.
4) Safety and diagnostics  
   - Track which rules fire and emit debug logs behind a flag. Include opt-in “unsafe but fast” rules (e.g. assumptions about `%eax` scratch) so riskier rewrites are gated.
5) Tests and fixtures  
   - Table-driven tests: input instruction slices -> expected output, plus golden files for short asm snippets. Add regression fixtures for every new rule.

## Quick Wins to Implement Early
- Fold `movl imm/reg, %tmp` followed by `movl %tmp, mem|reg` into a single move; appears constantly in the vtable setup code (`out/rubyspec_temp_alias_spec.s:1200`).
- Generalize redundant self-moves: drop `movl %r, %r` for any register (not just `%eax`).
- Broaden stack arithmetic folding: combine adjacent `addl`/`subl` pairs in either order when the window contains no `%esp` users; coalesce sequential `subl` of the same dest already seen.
- Push/pop cleanup: remove identical `push`/`pop` pairs even when separated by comments; rewrite `pushl %r; popl %s` to `movl %r, %s` when both are caller-saved and no memory touch in between.
- Constant compare shortening: turn `movl imm, %tmp` + `cmpl %tmp, reg` into `cmpl imm, reg` for any scratch tmp register, not only `%eax`.
- Stack store folding: `movl imm/reg, %tmp` + `movl %tmp, k(%esp|%ebp)` -> direct store, shrinking the hottest call-setup paths.

## Collecting Assembly Samples Systematically
- Build a small parser to tokenize `out/*.s` into normalized instructions (strip labels/comments, standardize registers/immediates, keep operand shapes).
- Compute frequent n-grams (2–5) and rank by cost (instruction count saved by ideal rewrite) to target the highest-volume patterns first.
- Capture deltas: run the parser before/after peephole changes to see which rules fire and how many instructions are removed; dump CSV/JSON for quick diffing.
- Sample diversity: gather one short snippet per distinct function (or every N lines) to keep analysis fast; store curated fixtures under `test/peephole_fixtures/`.
- Add a “hot path” mode: focus on prologue/epilogue and call setup regions where move-folding and stack math rules pay off immediately.
