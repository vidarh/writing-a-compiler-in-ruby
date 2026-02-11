SELFHOST

# Clean Self-Hosting Bootstrap

Achieve a fully clean three-stage bootstrap (MRI -> compiler1 -> compiler2 -> compiler3) with no workarounds, where compiler2 and compiler3 produce identical output, validating end-to-end correctness.

## Vision

The compiler source contains zero `@bug` workarounds and zero `FIXME` entries related to self-hosting limitations. The bootstrap process runs unattended: MRI compiles the compiler to produce compiler1, compiler1 compiles itself to produce compiler2, compiler2 compiles itself to produce compiler3, and compiler2 and compiler3 are byte-identical. Every Ruby construct used in the compiler's own source is handled correctly by the compiler itself, not worked around.

## Why This Matters

Self-hosting is the foundational correctness proof for a compiler. Every workaround in the compiler source is a place where the compiler cannot correctly compile its own language -- it is both a correctness gap and a maintenance burden. Eliminating workarounds means the compiler handles a strictly larger subset of Ruby, which feeds directly into spec compliance (COMPLANG) and enables writing the compiler in more idiomatic Ruby. A clean bootstrap also means contributors can write normal Ruby without fear of triggering compiler bugs.

## Sources

Where this goal was discovered:
- README.md (lines 70-83): Describes the three-stage bootstrap process as a core project goal, noting that compiler2 and compiler3 "should be identical" and step 3 "should be trivial" once step 2 works
- README.md (lines 88-93): Lists specific workarounds including exceptions (begin/rescue commented out), regexp (avoided), float (avoided), and notes "compiler code is littered with workarounds for specific bugs"
- README.md (lines 97-104): Post-bootstrap roadmap includes "Go through the current FIXME's and explicitly check which are still relevant; add test cases, and fix them in turn"
- CLAUDE.md: References `@bug` markers and `FIXME` comments throughout the compiler source as known workarounds
- docs/ARCHITECTURE.md (lines 183-187): Documents "Workarounds in Compiler Source" including `@bug` markers and `FIXME` comments

## Related Goals

- [COMPLANG](COMPLANG-compiler-advancement.md): Fixing compiler bugs improves both self-hosting and spec compliance; many `@bug` workarounds correspond to spec failures

## Potential Plans

Ideas for incremental plans that would advance this goal:
- Audit all `@bug` and `FIXME` markers in compiler source, classify by root cause, and prioritize by which fixes unblock the most workarounds
- Re-enable begin/rescue in the compiler source (currently commented out for bootstrap) by fixing exception handling
- Eliminate the most common category of workaround (e.g., string handling, method call patterns) with a targeted compiler fix
- Add a CI-style check that compares compiler2 and compiler3 assembly output and flags any divergence

---
*Status: GOAL*
