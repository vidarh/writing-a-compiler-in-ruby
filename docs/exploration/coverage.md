# Exploration Coverage

## Explored Areas

| Area | Date | Notes |
|------|------|-------|
| Compiler test infrastructure & AI enablement | 2026-02-10 | [compiler-test-infrastructure.md](compiler-test-infrastructure.md) |
| RubySpec compliance landscape | 2026-02-10 | [rubyspec-compliance-landscape.md](rubyspec-compliance-landscape.md) |
| Core library implementations (lib/core/) | 2026-02-14 | [core-library-implementations.md](core-library-implementations.md) |

## Not Yet Explored

- Parser architecture (recursive descent + shunting yard internals)
- Code generation and x86 assembly patterns
- Scope system (scope.rb, globalscope.rb, classcope.rb, funcscope.rb, etc.)
- Object model and type tagging (integers, heap objects, GC)
- Docker build environment and toolchain
- Bootstrap process and self-hosting mechanics
- Transform layer (transform.rb)
- Register allocation (regalloc.rb)

## Ideas Found

### From compiler-test-infrastructure exploration (2026-02-10)

- Crash root-cause catalog for "crashing" rubyspec files (24 of 47 have partial output)
- Failing spec priority matrix (which specs are closest to passing)
- Method coverage gap analysis (lib/core/ vs rubyspec expectations)
- Peephole rule mining via asm_ngram.rb
- run_rubyspec rewrite from bash/sed to Ruby

### From rubyspec-compliance-landscape exploration (2026-02-10)

- Quick-win suite expansion: run core/nil, core/true, core/false to show broader compliance
- Fix rubyspec_integer.txt truncation — integer suite likely has high pass rate
- Reclassify CRASH files with partial output as "PARTIAL" for more honest metrics
- Composite compliance metric: individual test pass rate across all suites
- Sed workaround impact analysis: compare with-workarounds vs without-workarounds results
- Near-passing file identification: rank files by (total - passed) for highest-ROI fixes
- Correct documentation metrics (TODO.md, KNOWN_ISSUES.md, COMPLANG goal) to reflect nuanced crash data

### From core-library-implementations exploration (2026-02-14)

- Quick-win spec expansion: run core/nil, core/true, core/false (36 specs, implementations ~complete)
- Core library FIXME audit: categorize ~140 FIXMEs in lib/core/ by type and rubyspec impact
- Method coverage gap analysis: compare lib/core/ methods against rubyspec/core/ expectations
- Enumerable module fix: investigate why `include Enumerable` doesn't work (blocks Array/Hash integration)
- Comparable implementation: 6 methods using `<=>`, unblocks 5 spec files
- Hash method stubs: add ~20 missing methods to convert crashes to failures
- String method gaps: ~70 missing methods, prioritize by rubyspec usage frequency
- Add Makefile targets for core/nil, core/true, core/false, core/symbol suites
