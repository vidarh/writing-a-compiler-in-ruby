HEREDOCESC
Created: 2026-02-11 04:04
Created: 2026-02-11

# Add Escape Sequence Processing to Interpolated Heredocs

[FUNCTIONALITY] Fix missing backslash escape handling in double-quoted heredoc bodies, which causes `\<newline>` (line continuation), `\n`, `\t`, and `\\` to be stored as raw characters instead of being resolved.

## Goal Reference

[COMPLANG](../../goals/COMPLANG-compiler-advancement.md)

## Root Cause

The heredoc body reader in [tokens.rb](../../../tokens.rb) (lines 962-1024) reads characters one-by-one into a buffer but never checks for backslash escapes. In contrast, double-quoted strings use `Quoted.escaped` ([quoted.rb](../../../quoted.rb) line 16) which resolves `\n` to LF, `\t` to TAB, `\\` to a single backslash, and `\<newline>` to nothing (line continuation). Heredocs skip this entirely -- every character including backslashes is stored verbatim.

This was confirmed by running `./run_rubyspec rubyspec/language/heredoc_spec.rb`:

```
  FAILED: Expected "a\nbc\n" but got "a\nb\\\nc\n"
```

The fixture (`rubyspec/language/fixtures/squiggly_heredoc.rb` line 33-37) contains `b\` at end-of-line followed by `c`. Ruby treats `\<newline>` in interpolated heredocs as line continuation, producing `bc`. The compiler stores the backslash and newline literally.

## Infrastructure Cost

Zero. This is a tokenizer fix in [tokens.rb](../../../tokens.rb). No new files, no build system changes. Validated by existing test infrastructure (`make selftest`, `make selftest-c`, `./run_rubyspec`).

## Scope

**In scope:**
- Add backslash escape processing to the heredoc body reader in [tokens.rb](../../../tokens.rb) for interpolated (non-single-quoted) heredocs, covering at minimum: `\n`, `\t`, `\r`, `\e`, `\\`, `\<newline>` (line continuation), and the pass-through `else` case
- Validate with `make selftest`, `make selftest-c`, and `./run_rubyspec rubyspec/language/heredoc_spec.rb`
- Update [docs/rubyspec_language.txt](../../rubyspec_language.txt) via `make rubyspec-language`

**Out of scope:**
- Escape handling in single-quoted heredocs (Ruby does not process escapes there, except `\\` and `\'`)
- Octal/hex/unicode escape sequences (`\0xx`, `\xNN`, `\uNNNN`) -- these can be a follow-up
- Fixing the other two heredoc_spec failures (one requires `eval`, one requires `NameError`)
- Escape handling in other string types (already handled by `Quoted.escaped`)

## Expected Payoff

- heredoc_spec.rb failure count drops from 3 to 2 (the backslash test passes; the remaining 2 require eval/NameError)
- Heredocs containing `\n`, `\t`, `\\`, or line continuations now work correctly throughout the compiler
- Advances individual test pass rate (currently 272/994 = 27%)
- May fix failures in other spec files that use escape sequences inside heredocs (e.g., string_spec.rb has 14 failures)

## Proposed Approach

In the heredoc body reading loop ([tokens.rb](../../../tokens.rb) around line 1021), when `interpolate` is true and the current character is `\` (backslash), peek at the next character and resolve the escape sequence -- either by calling `Quoted.escaped` or by inlining equivalent logic. The `\<newline>` case should consume both characters and produce nothing (line continuation). Other escapes follow the same rules as double-quoted strings.

## Acceptance Criteria

- [ ] `./run_rubyspec rubyspec/language/heredoc_spec.rb` shows the "allows HEREDOC with <<~'identifier', no interpolation, with backslash" test passing (14 of 16 pass, 2 remaining failures are eval/NameError-dependent)
- [ ] `make selftest` and `make selftest-c` both pass
- [ ] [docs/rubyspec_language.txt](../../rubyspec_language.txt) is updated via `make rubyspec-language` with no regression in overall pass count (272 or more individual tests passing)

## Open Questions

- Should the fix reuse `Quoted.escaped` directly (requires the scanner to be in a compatible state) or inline equivalent logic in the heredoc reader? Inlining may be simpler given the different reading context.

---
*Status: APPROVED (implicit via --exec)*