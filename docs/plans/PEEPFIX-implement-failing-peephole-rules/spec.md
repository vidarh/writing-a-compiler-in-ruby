PEEPFIX
Created: 2026-02-13

# Implement Two Failing Peephole Optimizer Rules

[CODEGEN] Add the push-pop-to-mov and immediate-compare-folding rules that are specified by existing unit tests but not yet implemented.

## Goal Reference

[CODEGEN](../../goals/CODEGEN-output-code-quality.md)

## Root Cause

[test/test_peephole.rb](../../../test/test_peephole.rb) defines 9 unit tests for the peephole optimizer. Two of them fail because the optimization rules they specify were written as test-first specifications but never implemented in [peephole.rb](../../../peephole.rb):

1. **`test_push_eax_pop_reg_becomes_mov`** (line 48): Expects `pushl %eax; popl %esi` to become `movl %eax, %esi`. The existing `handle_push_pop_patterns` only eliminates `pushl reg; popl same_reg` pairs (line 201) but does not convert cross-register push-pop sequences into moves.

2. **`test_mov_imm_eax_then_cmpl_eax_becomes_cmpl_imm`** (line 54): Expects `movl $5, %eax; cmpl %eax, %ecx` to become `cmpl $5, %ecx`. No rule in peephole.rb handles folding an immediate load into a subsequent compare.

Both patterns are documented as "quick wins" in [docs/peephole_optimizer_plan.md](../../peephole_optimizer_plan.md) (lines 25-28). The push-pop-to-mov pattern is common in generated code because the compiler uses the stack to shuttle values between registers. The immediate-compare pattern appears in conditionals where a constant is loaded into `%eax` solely to compare it.

## Infrastructure Cost

Zero. Both rules are additions to existing methods in [peephole.rb](../../../peephole.rb). No new files, no build system changes, no external dependencies. Validation uses existing `ruby test/test_peephole.rb` (runs under MRI, no Docker needed) plus `make selftest` and `make selftest-c` (Docker).

## Scope

**In scope:**
- Add push-pop-to-mov rule: `pushl reg; popl other_reg` -> `movl reg, other_reg` in `handle_push_pop_patterns`
- Add immediate-compare-fold rule: `movl imm, %eax; cmpl %eax, reg` -> `cmpl imm, reg` (when next instruction overwrites `%eax` or `%eax` is not needed)
- Validate with unit tests, `make selftest`, and `make selftest-c`

**Out of scope:**
- The peephole2.rb refactor (Stage 1 of [peephole_refactor_steps.md](../../peephole_refactor_steps.md))
- Adding liveness analysis or safety guards (these rules are safe without them -- push-pop-to-mov preserves semantics by construction, and the immediate-compare fold matches the existing `handle_mov_chain` pattern which already folds through `%eax` without liveness checks)
- Mining new patterns from assembly output
- Instruction count measurements (bonus, not required)

## Expected Payoff

- All 9 peephole unit tests pass (currently 7/9)
- Reduced instruction count in compiled output from eliminating redundant push/pop pairs and movl-then-cmpl sequences
- Direct progress on [CODEGEN](../../goals/CODEGEN-output-code-quality.md), which currently has zero active plans

## Proposed Approach

1. In `handle_push_pop_patterns`: add a case for `pushl reg; popl other_reg` (where reg != other_reg) that replaces both with `movl reg, other_reg`
2. In `peephole` or `handle_simple_patterns`: add a case for `movl imm, %eax; cmpl %eax, reg` that replaces both with `cmpl imm, reg` -- following the same eax-forwarding pattern used by `handle_mov_chain`
3. Run `ruby test/test_peephole.rb` to verify both tests pass
4. Run `make selftest` and `make selftest-c` to verify no regressions

## Acceptance Criteria

- [ ] `ruby test/test_peephole.rb` reports 9 runs, 0 failures (currently 2 failures)
- [ ] `make selftest` and `make selftest-c` both pass
- [ ] No existing peephole test regresses

---
*Status: PROPOSAL - Awaiting approval*
