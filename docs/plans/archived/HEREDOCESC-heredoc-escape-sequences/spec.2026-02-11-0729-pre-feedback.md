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

## Implementation Details

### File to modify

**[tokens.rb](../../../tokens.rb):962-1024** — The heredoc body reading loop. Specifically, the escape handling must be inserted into the inner character-reading loop (line 964-1024) as a new condition checked *before* the existing `else` branch at line 1021.

### Insertion point

The inner loop at [tokens.rb](../../../tokens.rb):964 reads characters one at a time:

```ruby
while @s.peek && @s.peek != ?\n
  c = @s.get.chr
  if interpolate && c == "#" && @s.peek   # line 968 — interpolation
    ...
  else                                     # line 1021 — default: append char
    line << c
  end
end
```

A new `elsif` branch must be added between the interpolation check (line 968) and the `else` (line 1021), matching the pattern:

```ruby
elsif interpolate && c == "\\"
  # backslash escape handling
```

### Escape sequences to handle

The logic should mirror [quoted.rb](../../../quoted.rb):16-67 (`Quoted.escaped`) but inlined, since `Quoted.escaped` reads the *first* character itself (which we've already consumed as `c`) and checks for a quote terminator (inapplicable to heredocs). The cases to handle:

| Sequence | Behaviour | Notes |
|----------|-----------|-------|
| `\n` | Append LF (10.chr) | Match `Quoted.escaped` line 28 |
| `\t` | Append TAB (9.chr) | Match `Quoted.escaped` line 26 |
| `\r` | Append CR (13.chr) | Not in `Quoted.escaped` — add explicitly |
| `\e` | Append ESC (27.chr) | Match `Quoted.escaped` line 24 |
| `\\` | Append single `\` | Falls through `else` in `Quoted.escaped` line 63 |
| `\#` | Append literal `#` | Prevents interpolation; `Quoted.escaped` returns `:escaped_hash` — here just append `"#"` |
| `\<newline>` | Consume both, output nothing (line continuation) | **Special**: `@s.peek == ?\n` when we see `\`; must consume the newline *inside* the inner loop so the outer loop doesn't see a false line-end |
| `\<other>` | Append backslash + the character as-is | Pass-through matches `Quoted.escaped` line 63 (`else return e`) but we also preserve the backslash for unknown escapes, matching Ruby's behaviour (`"\q" == "\\q"`) |

### Line continuation subtlety

The inner loop condition is `@s.peek != ?\n`. When `\` is the last character on a line, `@s.peek` is `?\n`. The escape handler must:
1. Detect `@s.peek == ?\n` after seeing the backslash.
2. Consume the newline via `@s.get`.
3. **Not** append anything to `line` (the backslash and newline are both absorbed).
4. The inner loop then continues reading the *next* line's characters without breaking, because after consuming `\n`, `@s.peek` will be the first character of the next line (not `?\n`).

### `\#` handling

In `Quoted.escaped`, `\#` returns the special marker `:escaped_hash`, which the caller in `expect_dquoted` converts to a literal `"#"` in the buffer. In the heredoc reader, since we control the buffer directly, we simply append `"#"` to `line`. This prevents the `#` from being picked up as interpolation on the next iteration.

### Pass-through (`else`) behaviour

Ruby preserves unknown backslash sequences literally: `"\q"` produces the two-character string `\q`. So the `else` case should append both `"\\"` and the next character to `line`. This matches `Quoted.escaped`'s `else` at line 63 (which returns `e`, the character after the backslash — but there the caller never sees the backslash at all, so effectively `\q` → `q`). **Correction**: `Quoted.escaped` consumes the backslash and returns only the next character, making `\q` → `q`. Ruby's actual behaviour for double-quoted strings is `\q` → `\q` (preserves backslash for unknown escapes). The `Quoted.escaped` behavior already handles this correctly for known escapes; for unknown escapes in heredocs we should append just the next character (matching `Quoted.escaped`'s behaviour for consistency, even though Ruby would preserve the backslash). This keeps heredocs consistent with the compiler's existing double-quoted string handling.

### No other files need changes

- [quoted.rb](../../../quoted.rb) — No changes needed (its `escaped` method is for regular strings and works correctly).
- [scanner.rb](../../../scanner.rb) — No changes needed (scanner API is sufficient).
- [parser.rb](../../../parser.rb) — No changes needed.
- Build system — No changes needed.

### Existing patterns to follow

The escape handling should use the same constants as [quoted.rb](../../../quoted.rb):4-7 but defined locally or accessed via the module, since [tokens.rb](../../../tokens.rb) is inside `module Tokens` and `Quoted` is `Tokens::Quoted`:
- `Quoted::TAB` = `9.chr`
- `Quoted::LF` = `10.chr`
- `Quoted::ESC` = `27.chr`

Alternatively, inline the character literals directly (e.g., `"\n"`, `"\t"`, `"\e"`) since the compiler handles these in regular string literals.

### Edge cases

1. **Backslash at EOF** — If `\` is the very last character in a heredoc body (before the closing marker), `@s.peek` may be `nil`. The code should handle this by appending the backslash literally.
2. **Backslash before closing marker** — If a line is `\<newline>MARKER`, line continuation consumes the newline, so the next iteration reads `MARKER` as part of the continued line, not as a closing marker. This is correct Ruby behaviour.
3. **Single-quoted heredocs** — The `interpolate` variable (set at line 957: `interpolate = (quote_char != ?')`) already guards the condition, so single-quoted heredocs are unaffected.

## Execution Steps

1. [ ] **Add escape handling branch to heredoc body reader** — In [tokens.rb](../../../tokens.rb):1021, insert a new `elsif interpolate && c == "\\"` branch before the existing `else` clause. Implement the escape cases: `\n` → LF, `\t` → TAB, `\r` → CR, `\e` → ESC, `\#` → literal `#`, `\\` → single backslash, `\<newline>` → consume newline and produce nothing (line continuation), `\<other>` → pass through as the character after the backslash. Handle `@s.peek == nil` (EOF after backslash) by appending backslash literally.

2. [ ] **Run `make selftest`** — Verify the compiler still self-tests correctly. No heredocs with escape sequences exist in the compiler source, so this should pass unchanged.

3. [ ] **Run `make selftest-c`** — Verify the self-compiled compiler also passes.

4. [ ] **Run `./run_rubyspec rubyspec/language/heredoc_spec.rb`** — Verify the backslash test now passes (expect 14/16 passing, 2 remaining failures for eval/NameError tests).

5. [ ] **Run `make rubyspec-language`** — Update [docs/rubyspec_language.txt](../../rubyspec_language.txt) and verify no regression in overall pass count (272 or more individual tests passing).

6. [ ] **Commit** — Stage [tokens.rb](../../../tokens.rb) and [docs/rubyspec_language.txt](../../rubyspec_language.txt), commit with message describing the escape sequence fix.


## User Feedback (2026-02-11 07:27)

Execution failed. Retrying. Note that the current implementation approach is categorically *REJECTED* for being a horrific hack

---
*Status: APPROVED (implicit via --exec)*