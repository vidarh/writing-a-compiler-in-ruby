COMPLANG

# Autonomous Compiler Spec Progression

Advance the Ruby-in-Ruby compiler toward full language spec compliance through autonomous AI-driven improvement cycles, systematically increasing the pass rate from the current 4% baseline.

## Vision

The compiler has a robust test infrastructure: 78 rubyspec files, a selftest suite, a Docker build environment, and a detailed bug catalog in docs/TODO.md with prioritized issues. This makes it an ideal candidate for autonomous improvement -- each change can be validated against the spec suite with clear pass/fail output. The improvement pipeline proposes plans targeting specific spec failures, and each executed plan measurably advances the pass rate.

Over time, the compiler progresses from 3/78 passing spec files toward broader language compliance, driven by a steady cadence of autonomously generated and executed improvement plans rather than sporadic manual sessions.

## Why This Matters

- The compiler is the single best candidate in the codebase for autonomous AI iteration: deterministic test output, clear bug catalog, and a strict CLAUDE.md preventing dangerous shortcuts
- The 4% pass rate (3 of 78 files) means there is enormous headroom for improvement -- dozens of spec files that crash or fail with known, documented causes
- Each spec file fixed is a concrete, measurable outcome that validates the autonomous improvement approach
- The compiler is a long-running personal project that stalls without activation energy -- autonomous planning removes the barrier to steady progress

## Sources

- [docs/TODO.md](../TODO.md): Test status (3/78 passing), prioritized bug list with effort estimates
- [CLAUDE.md](../../CLAUDE.md): Strict guardrails preventing dangerous compiler modifications
- Selftest suite: All passing (selftest and selftest-c)
- Docker build environment for isolated compilation testing
- [docs/exploration/rubyspec-compliance-landscape.md](../exploration/rubyspec-compliance-landscape.md): Detailed analysis showing 272/994 individual test pass rate (27%), 24 of 47 "crash" files actually have partial output, and the full rubyspec has 3,781 files (language/ is only 2% of the suite)
- [docs/exploration/compiler-test-infrastructure.md](../exploration/compiler-test-infrastructure.md): Documents the test tiers, autonomous workflow skills, and identifies the spec-by-spec fix workflow as the primary autonomous improvement path
- [docs/REGEXP_IMPLEMENTATION_PLAN.md](../REGEXP_IMPLEMENTATION_PLAN.md): Regexp phases 0-5 complete (42% pass rate), phases 6-7 (NFA/DFA, Ruby-specific features) not started
- [docs/PATTERN_MATCHING_STATUS.md](../PATTERN_MATCHING_STATUS.md): Pattern matching partially implemented (3 of 10+ pattern types), compiles but runtime incomplete

## Related Goals

- [PARSARCH](PARSARCH-parser-architecture.md): Parser unification directly unblocks 5+ language specs by making control flow structures work as expressions
- [SELFHOST](SELFHOST-clean-bootstrap.md): Many `@bug` workarounds in the compiler correspond to spec failures; fixing them advances both goals
- [CODEGEN](CODEGEN-output-code-quality.md): Better codegen reduces GC pressure, potentially converting some crashes to passes

## Potential Plans

Ideas for incremental plans the improvement pipeline may generate:
- Fix specific crashing spec files by addressing documented issues in TODO.md (e.g. break semantics, exception handling, string encoding)
- Add missing standard library method stubs that cause spec crashes
- Improve error handling in the compiler to convert crashes into failures (making more specs runnable)
- Address the "Medium Effort" priority items in TODO.md that unblock multiple spec files at once

---
*Status: GOAL*
