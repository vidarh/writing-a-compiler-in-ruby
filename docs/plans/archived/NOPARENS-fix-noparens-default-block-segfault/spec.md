NOPARENS
Created: 2026-02-10 23:35

# Fix Segfault: Method Calls Without Parens + Default Params + Block

[FUNCTIONALITY] Fix the compiler bug where calling a method without parentheses when the method has default parameters and a block argument causes a segfault at runtime.

## Goal Reference

[COMPLANG](../../goals/COMPLANG-compiler-advancement.md)

## Root Cause

The compiler generates incorrect argument-passing code when a method call omits parentheses and the method signature includes both default parameters and a block parameter. Specifically, this crashes:

```ruby
def foo(a, b = 1, &block)
  block.call
end
foo :x, :y do
  puts "hi"
end
```

while the parenthesized equivalent `foo(:x, :y) do ... end` works correctly.

The root cause is in argument count resolution during code generation. When parentheses are absent, the parser/compiler cannot correctly determine where the argument list ends and the block begins, leading to misaligned stack frames that segfault at runtime. The [run_rubyspec](../../run_rubyspec) script works around this with sed transformations (lines 112-114) that add parentheses to `describe` and `it_behaves_like` calls, but these sed workarounds themselves break specs with multi-line lambda arguments (documented in [rubyspec_runner_limitations.md](../rubyspec_runner_limitations.md), affecting at least magic_comment_spec.rb and predefined_spec.rb).

The bug exists at the boundary between [parser.rb](../../parser.rb) and [compile_calls.rb](../../compile_calls.rb): the parser produces an AST where the block attachment and argument count are incorrect for the no-parens case.

## Infrastructure Cost

Zero. This is a compiler fix validated by existing test infrastructure (`make selftest`, `make selftest-c`, `./run_rubyspec`). No new tools, no build system changes.

## Prior Plans

No prior plans have targeted this specific compiler bug. The [SPECPICK](../archived/SPECPICK-rubyspec-target-picker/spec.md) and [SPECWIDE](../archived/SPECWIDE-broad-rubyspec-baseline/spec.md) plans addressed tooling and automation around spec results. [CASEFIX](../archived/CASEFIX-fix-case-spec-crash/spec.md) targeted a specific spec file crash without validation. This plan targets a validated, documented compiler bug with a known reproduction case and known downstream effects on the test infrastructure.

## Scope

**In scope:**
- Diagnose the exact code generation difference between `foo(:x, :y) do ... end` and `foo :x, :y do ... end` when `foo` has default params
- Fix the parser or compiler so both forms produce correct code
- Validate with `make selftest`, `make selftest-c`
- Remove the `describe` and `it_behaves_like` parenthesization sed workarounds from [run_rubyspec](../../run_rubyspec)
- Re-run `make rubyspec-language` and capture updated results

**Out of scope:**
- Fixing other sed workarounds (hash literals in method+block, instance variable rewriting, etc.)
- Fixing any spec failures exposed by removing the sed workarounds (those are future plans)

## Expected Payoff

- Eliminates a class of runtime segfaults from a common Ruby calling convention
- Removes two fragile sed workarounds from [run_rubyspec](../../run_rubyspec), making spec results more honest
- Unblocks at least magic_comment_spec.rb and predefined_spec.rb which currently fail due to sed mangling
- Advances the compiler toward handling real-world Ruby code that mixes blocks with default parameters
- Makes the rubyspec results more trustworthy by reducing test infrastructure interference

## Proposed Approach

1. Compile the documented reproduction case with and without parentheses, diff the generated assembly to identify where the code diverges
2. Trace the divergence back to the parser AST or the `compile_calls.rb` code generation
3. Fix the root cause so both forms generate equivalent code
4. Validate with selftest/selftest-c
5. Remove the sed parenthesization workarounds from run_rubyspec
6. Re-run `make rubyspec-language` to capture improved results

## Acceptance Criteria

- [ ] The reproduction case (`def foo(a, b = 1, &block); block.call; end; foo :x, :y do puts "hi" end`) compiles and runs without segfault
- [ ] `make selftest` and `make selftest-c` both pass
- [ ] The `describe` and `it_behaves_like` parenthesization sed lines are removed from [run_rubyspec](../../run_rubyspec)
- [ ] `make rubyspec-language` results are updated in [rubyspec_language.txt](../rubyspec_language.txt) with no regression in pass count (272 individual tests or more)

---
*Status: REJECTED — Wrong focus to do this rather than improve automation of fixes.*