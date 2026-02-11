CODEGEN

# Output Code Quality

Produce efficient, well-optimized x86 assembly output through a maintainable peephole optimizer and, eventually, proper optimization passes, reducing instruction count and improving runtime performance of compiled programs.

## Vision

The compiler's generated assembly is compact and efficient. The peephole optimizer uses a data-driven rule system with safety guards (register liveness, operand classification) that makes adding new rules straightforward and provably safe. Generated code avoids redundant moves, unnecessary push/pop pairs, and trivially eliminable instructions. Optimization impact is measurable through instruction count deltas and runtime benchmarks. Over time, the optimizer grows from peephole rules to more sophisticated passes (dead code elimination, register allocation improvements, basic inlining).

## Why This Matters

Code quality directly affects the usability of compiled programs. The compiler currently generates verbose assembly with many redundant instruction sequences (push/pop of scratch registers, mov-to-eax chains, adjacent stack adjustments). Improving output quality makes the compiler viable for real programs, reduces binary size, and improves execution speed. The peephole optimizer is also one of the safest areas for autonomous improvement since changes are validated by selftest/selftest-c with clear before/after instruction count metrics.

## Sources

Where this goal was discovered:
- README.md (line 25): "Proper optimization (the peephole optimizer is a crude stopgap)"
- docs/peephole_optimizer_plan.md: Detailed plan for peephole refactoring including rule structs, operand normalization, liveness hints, tracing hooks, and fixture-based testing
- docs/peephole_refactor_steps.md: Five-stage refactoring plan from baseline stabilization through data-driven rule expansion to switch-over
- docs/exploration/compiler-test-infrastructure.md (lines 161-166): Identifies peephole optimizer expansion as a safe area for autonomous work with existing tooling (asm_ngram.rb, compare_asm.rb)
- docs/ARCHITECTURE.md (lines 254-263): Documents current performance bottlenecks including "No inlining or advanced optimizations"
- peephole.rb: 247-line peephole optimizer with 8 unit tests, already functional but with rules relying on comments instead of safety checks

## Related Goals

- [COMPLANG](COMPLANG-compiler-advancement.md): Better codegen does not directly improve spec pass rates, but more efficient code reduces GC pressure (fewer allocations from redundant object creation) which can convert some crashes to passes
- [SELFHOST](SELFHOST-clean-bootstrap.md): Peephole improvements are validated through self-hosting (selftest-c), ensuring optimized output still bootstraps correctly

## Potential Plans

Ideas for incremental plans that would advance this goal:
- Implement Stage 1 of peephole_refactor_steps.md: the shared Instruction model and Rule structs in a side-by-side peephole2.rb
- Add operand classification (reg/mem/imm) and a scratch_dead? guard to enable safe mov-chain folding
- Mine top instruction n-grams from out/selftest.s using tools/asm_ngram.rb and implement rules for the top 3 patterns
- Add rule-firing counters and a before/after instruction count comparison to the test infrastructure

---
*Status: GOAL*
