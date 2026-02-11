HEREDOCESC
Created: 2026-02-11 04:04
Created: 2026-02-11

# Add Escape Sequence Processing to Interpolated Heredocs

> **User direction (2026-02-11 07:36):** Stopped the execution because the agent has kept an execution plan which entirely unreasonably duplicates code by handling HEREDOC escaping separate from other escaping. A HEREDOC is simply an escaped string. This escape string simply has an extra option: dedent based on the indentation of the start marker. No implementation that doesn't build on the same tokenization code as for other quoted strings will be accepted.

[FUNCTIONALITY] Fix missing backslash escape handling in double-quoted heredoc bodies by reusing the same tokenization code that handles escapes in other quoted strings (`Quoted.escaped`). A heredoc is simply an escaped string with an extra option: dedent based on the indentation of the start marker. The escape handling must not be duplicated.

## Goal Reference

[COMPLANG](../../goals/COMPLANG-compiler-advancement.md)

## Root Cause

The heredoc body reader in [tokens.rb](../../../tokens.rb) reads characters one-by-one into a buffer but never calls `Quoted.escaped` ([quoted.rb](../../../quoted.rb) line 16) to resolve backslash escapes. Double-quoted strings already use `Quoted.escaped` which resolves `\n` to LF, `\t` to TAB, `\\` to a single backslash, `\<newline>` to nothing (line continuation), `\M-`, `\C-`, `\c-` meta/control escapes, and `\#` to prevent interpolation. Heredocs skip this entirely — every character including backslashes is stored verbatim.

This was confirmed by running `./run_rubyspec rubyspec/language/heredoc_spec.rb`:

```
  FAILED: Expected "a\nbc\n" but got "a\nb\\\nc\n"
```

The fixture (`rubyspec/language/fixtures/squiggly_heredoc.rb` line 33-37) contains `b\` at end-of-line followed by `c`. Ruby treats `\<newline>` in interpolated heredocs as line continuation, producing `bc`. The compiler stores the backslash and newline literally.

## Infrastructure Cost

Zero. This is a tokenizer fix in [tokens.rb](../../../tokens.rb). No new files, no build system changes. Validated by existing test infrastructure (`make selftest`, `make selftest-c`, `./run_rubyspec`).

## Scope

**In scope:**
- Modify the heredoc body reader in [tokens.rb](../../../tokens.rb) to call `Quoted.escaped` for escape processing in interpolated (non-single-quoted) heredocs, reusing the same code path that double-quoted strings use
- Escape handling must be uniform for all heredoc types (regular and squiggly) — no special-casing per heredoc style
- Dedent for squiggly heredocs must happen during tokenization, operating on already-escaped content
- Validate with `make selftest`, `make selftest-c`, and `./run_rubyspec rubyspec/language/heredoc_spec.rb`
- Update [docs/rubyspec_language.txt](../../rubyspec_language.txt) via `make rubyspec-language`

**Out of scope:**
- Escape handling in single-quoted heredocs (Ruby does not process escapes there, except `\\` and `\'`)
- Fixing the other two heredoc_spec failures (one requires `eval`, one requires `NameError`)

## Expected Payoff

- heredoc_spec.rb failure count drops from 3 to 2 (the backslash test passes; the remaining 2 require eval/NameError)
- Heredocs containing `\n`, `\t`, `\\`, or line continuations now work correctly throughout the compiler
- Advances individual test pass rate (currently 272/994 = 27%)
- May fix failures in other spec files that use escape sequences inside heredocs (e.g., string_spec.rb has 14 failures)

## Proposed Approach

**A heredoc is simply an escaped string.** The escape handling for heredoc bodies must reuse `Quoted.escaped` — the same method that double-quoted strings use. No duplicate escape table, no separate escape implementation.

When the heredoc body reader encounters a backslash in an interpolated heredoc, it must delegate to `Quoted.escaped` to resolve the escape, exactly as `Quoted.expect_dquoted` does. This ensures heredocs automatically get the same escape coverage (including `\M-`, `\C-`, `\e`, `\#`, etc.) without duplicating any logic.

The only heredoc-specific behaviour beyond normal string escaping is: squiggly heredocs (`<<~`) dedent based on the indentation of the start marker. This dedent happens during tokenization, operating on already-escaped content. Dedent is a layout operation that strips leading whitespace — it has nothing to do with escape handling.

**Categorically rejected approaches:**
- Implementing a separate escape table/switch in the heredoc reader (code duplication)
- Special-casing escape handling for squiggly heredocs
- Post-processing escapes after dedent
- Any approach where heredoc escapes and double-quoted string escapes are handled by different code

## Acceptance Criteria

- [ ] `./run_rubyspec rubyspec/language/heredoc_spec.rb` shows the backslash test passing (14 of 16 pass, 2 remaining failures are eval/NameError-dependent)
- [ ] `make selftest` and `make selftest-c` both pass
- [ ] [docs/rubyspec_language.txt](../../rubyspec_language.txt) is updated via `make rubyspec-language` with no regression in overall pass count (272 or more individual tests passing)
- [ ] Heredoc escape handling calls `Quoted.escaped` — no duplicate escape table in the heredoc reader
- [ ] No special-casing of escape handling by heredoc type — the escape branch is identical for regular and squiggly heredocs
- [ ] No post-processing of escapes after dedent — all escape resolution happens during tokenization

## Open Questions

- `Quoted.escaped` currently handles `\<newline>` line continuation internally (the scanner consumes both characters). Need to verify this works correctly in the heredoc context where line boundaries have additional significance (the outer loop checks for `\n` to detect line endings and the closing marker). If `Quoted.escaped` consumes a `\<newline>`, the heredoc loop must not also try to process that newline as a line boundary.

## Implementation Details

### Core principle

A heredoc is a quoted string. The escape handling code is `Quoted.escaped`. The heredoc reader must call `Quoted.escaped` for escape processing, not reimplement it.

### File to modify

**[tokens.rb](../../../tokens.rb)** — The heredoc body reading loop (around line 1015-1094).

### Current code to replace

The current heredoc body reader has a hand-rolled escape handler (lines 1072-1090) with its own `case` statement duplicating what `Quoted.escaped` already does:

```ruby
elsif interpolate && c == "\\"
  if @s.peek == ?\n
    @s.get
  elsif @s.peek == nil
    line << "\\"
  else
    nc = @s.get.chr
    case nc
    when "n" then line << "\n"
    when "t" then line << "\t"
    # ... etc
    end
  end
```

This entire block must be replaced with a call to `Quoted.escaped`.

### How to integrate `Quoted.escaped`

`Quoted.escaped(s, q)` takes the scanner `s` and a quote character `q`. It:
1. Peeks at the next character; returns `nil` if it matches `q` (end of string)
2. Gets the next character
3. If it's a backslash, gets the following character and resolves the escape
4. Returns the resolved character (or `:escaped_hash` for `\#`)

For heredoc usage: when the heredoc body reader encounters a character during an interpolated heredoc, instead of getting the character directly and then checking for backslash, it should call `Quoted.escaped(@s)` (with no quote character that could match, since heredocs don't end with a quote — they end with a marker on its own line). The quote character parameter needs to be set to something that won't appear in the stream at that position (or `Quoted.escaped` needs a minor adaptation to work without a terminating quote character in heredoc mode).

Alternatively, since the heredoc reader already gets character `c` and checks `c == "\\"`, it can unget `c` and call `Quoted.escaped(@s)` when a backslash is found, or restructure to call `Quoted.escaped` for each character.

The exact integration approach should be determined by reading the code — the key requirement is that `Quoted.escaped` (the same code, not a copy) handles the escape resolution.

### Line continuation special case

`Quoted.escaped` currently returns the escaped character. For `\<newline>` (line continuation), the scanner already sees the backslash and then `\n`. `Quoted.escaped` handles this by returning `nil` or empty — verify the actual behaviour and ensure the heredoc loop correctly handles the return value so that line continuation works (the `\` and newline are both consumed, nothing is added to the buffer).

### Squiggly heredoc dedent

The existing dedent code operates on the string content after the body reading loop. Since escapes are resolved during tokenization (via `Quoted.escaped`), the dedent operates on already-escaped content. This is correct — dedent strips leading whitespace from lines, and escaped characters are just characters in the string at that point.

### No other files need changes

- [quoted.rb](../../../quoted.rb) — May need minor adaptation if `Quoted.escaped`'s quote-character parameter doesn't work cleanly for heredoc context, but the escape resolution logic itself must not be duplicated.
- [scanner.rb](../../../scanner.rb) — No changes needed.
- [parser.rb](../../../parser.rb) — No changes needed.
- Build system — No changes needed.

## Execution Steps

1. [ ] **Replace the hand-rolled escape handler with a call to `Quoted.escaped`** — In [tokens.rb](../../../tokens.rb), remove the duplicated escape `case` statement (lines 1072-1090) and replace it with a call to `Quoted.escaped(@s)`. Handle the return value correctly: `:escaped_hash` → append `#`, `nil` → nothing (line continuation consumed the newline), otherwise append the returned character. Ensure line continuation (`\<newline>`) works correctly in the heredoc context — the consumed newline must not trigger the outer loop's line-end detection.

2. [ ] **Run `make selftest`** — Verify the compiler still self-tests correctly.

3. [ ] **Run `make selftest-c`** — Verify the self-compiled compiler also passes.

4. [ ] **Run `./run_rubyspec rubyspec/language/heredoc_spec.rb`** — Verify the backslash test now passes (expect 14/16 passing, 2 remaining failures for eval/NameError tests).

5. [ ] **Run `make rubyspec-language`** — Update [docs/rubyspec_language.txt](../../rubyspec_language.txt) and verify no regression in overall pass count (272 or more individual tests passing).

6. [ ] **Commit** — Stage [tokens.rb](../../../tokens.rb), any changes to [quoted.rb](../../../quoted.rb), and [docs/rubyspec_language.txt](../../rubyspec_language.txt), commit with message describing the escape sequence fix.

---
*Status: APPROVED (implicit via --exec)*
