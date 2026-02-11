HEREDOCESC
Created: 2026-02-11 04:04
Created: 2026-02-11

# Add Escape Sequence Processing to Interpolated Heredocs

> **User direction (2026-02-11 07:29):** Stopped the execution because the agent was proposing some truly horrific bullshit, like special casing escape handling in squiggly heredocs and post-processing the dedent, instead of dedenting during tokenization.

[FUNCTIONALITY] Fix missing backslash escape handling in double-quoted heredoc bodies, which causes `\<newline>` (line continuation), `\n`, `\t`, and `\\` to be stored as raw characters instead of being resolved.

## Goal Reference

[COMPLANG](../../goals/COMPLANG-compiler-advancement.md)

## Root Cause

The heredoc body reader in [tokens.rb](../../../tokens.rb) reads characters one-by-one into a buffer but never checks for backslash escapes. In contrast, double-quoted strings use `Quoted.escaped` ([quoted.rb](../../../quoted.rb) line 16) which resolves `\n` to LF, `\t` to TAB, `\\` to a single backslash, and `\<newline>` to nothing (line continuation). Heredocs skip this entirely -- every character including backslashes is stored verbatim.

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
- Escape handling must be uniform for all heredoc types (regular and squiggly) — no special-casing per heredoc style
- Dedent for squiggly heredocs must happen during tokenization, operating on already-escaped content
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

**All escape processing happens during tokenization, before dedent.** The escape handling branch in the heredoc body reading loop must be the same for regular and squiggly heredocs — no special-casing by heredoc style. When `interpolate` is true and the current character is `\` (backslash), peek at the next character and resolve the escape sequence inline.

The squiggly heredoc dedent then operates on the already-escaped string content. This is the correct order: escapes are a property of the string literal's quoting, and dedent is a layout operation that strips leading whitespace. Dedent does not need to know about escapes, and escapes do not need to know about dedent.

**Categorically rejected approaches:**
- Special-casing escape handling for squiggly heredocs (e.g., deferring escapes, storing raw backslash sequences)
- Post-processing escapes after dedent (e.g., a `process_heredoc_escapes` method called after indentation stripping)
- Any approach where squiggly and regular heredocs have different escape handling paths

## Acceptance Criteria

- [ ] `./run_rubyspec rubyspec/language/heredoc_spec.rb` shows the backslash test passing (14 of 16 pass, 2 remaining failures are eval/NameError-dependent)
- [ ] `make selftest` and `make selftest-c` both pass
- [ ] [docs/rubyspec_language.txt](../../rubyspec_language.txt) is updated via `make rubyspec-language` with no regression in overall pass count (272 or more individual tests passing)
- [ ] No special-casing of escape handling by heredoc type — the escape branch is identical for regular and squiggly heredocs
- [ ] No post-processing of escapes after dedent — all escape resolution happens in the character-reading loop

## Open Questions

None.

## Implementation Details

### File to modify

**[tokens.rb](../../../tokens.rb)** — The heredoc body reading loop.

### Escape handling in the character-reading loop

The escape handling branch must be a single `elsif interpolate && c == "\\"` with no distinction between squiggly and non-squiggly heredocs. It resolves escapes immediately as characters are read into the line buffer.

The cases to handle:

| Sequence | Behaviour | Notes |
|----------|-----------|-------|
| `\n` | Append LF (10.chr) | |
| `\t` | Append TAB (9.chr) | |
| `\r` | Append CR (13.chr) | |
| `\e` | Append ESC (27.chr) | |
| `\\` | Append single `\` | |
| `\#` | Append literal `#` | Prevents interpolation |
| `\<newline>` | Consume both, output nothing (line continuation) | Must consume the newline inside the inner loop so the outer loop doesn't see a false line-end |
| `\<other>` | Append the character after the backslash | Match `Quoted.escaped` behaviour for consistency with existing double-quoted string handling |

### Line continuation

When `\` is the last character on a line, `@s.peek` is `?\n`. The escape handler must:
1. Detect `@s.peek == ?\n` after seeing the backslash.
2. Consume the newline via `@s.get`.
3. **Not** append anything to `line` (the backslash and newline are both absorbed).
4. The inner loop continues reading the next line's characters.

### Squiggly heredoc dedent

The existing dedent code operates on the string content after the body reading loop. Since escapes are now resolved during tokenization, the dedent operates on already-escaped content. This is correct — dedent strips leading whitespace from lines, and escaped characters (like `\n` becoming a real newline, or `\t` becoming a real tab) are just characters in the string at that point.

**Remove**: Any post-processing escape code (like `process_heredoc_escapes`) that was added to handle escapes after dedent. Any squiggly-specific branches in the escape handling `elsif`.

### Edge cases

1. **Backslash at EOF** — If `\` is the very last character in a heredoc body (before the closing marker), `@s.peek` may be `nil`. Append the backslash literally.
2. **Backslash before closing marker** — If a line is `\<newline>MARKER`, line continuation consumes the newline, so the next iteration reads `MARKER` as part of the continued line, not as a closing marker. This is correct Ruby behaviour.
3. **Single-quoted heredocs** — The `interpolate` variable guards the condition, so single-quoted heredocs are unaffected.

### No other files need changes

- [quoted.rb](../../../quoted.rb) — No changes needed.
- [scanner.rb](../../../scanner.rb) — No changes needed.
- [parser.rb](../../../parser.rb) — No changes needed.
- Build system — No changes needed.

## Execution Steps

1. [ ] **Add uniform escape handling branch to heredoc body reader** — In [tokens.rb](../../../tokens.rb), the `elsif interpolate && c == "\\"` branch must handle all escape sequences identically for regular and squiggly heredocs. Remove any squiggly-specific branching. Implement: `\n` → LF, `\t` → TAB, `\r` → CR, `\e` → ESC, `\#` → literal `#`, `\\` → single backslash, `\<newline>` → consume newline and produce nothing (line continuation), `\<other>` → pass through as the character after the backslash. Handle `@s.peek == nil` (EOF after backslash) by appending backslash literally.

2. [ ] **Remove post-processing escape code** — Delete the `process_heredoc_escapes` method and any call sites. Delete any post-dedent escape processing block. Escapes are fully resolved during tokenization.

3. [ ] **Run `make selftest`** — Verify the compiler still self-tests correctly.

4. [ ] **Run `make selftest-c`** — Verify the self-compiled compiler also passes.

5. [ ] **Run `./run_rubyspec rubyspec/language/heredoc_spec.rb`** — Verify the backslash test now passes (expect 14/16 passing, 2 remaining failures for eval/NameError tests).

6. [ ] **Run `make rubyspec-language`** — Update [docs/rubyspec_language.txt](../../rubyspec_language.txt) and verify no regression in overall pass count (272 or more individual tests passing).

7. [ ] **Commit** — Stage [tokens.rb](../../../tokens.rb) and [docs/rubyspec_language.txt](../../rubyspec_language.txt), commit with message describing the escape sequence fix.

---
*Status: APPROVED (implicit via --exec)*
