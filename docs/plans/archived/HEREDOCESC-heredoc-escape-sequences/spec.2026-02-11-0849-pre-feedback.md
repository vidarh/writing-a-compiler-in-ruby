HEREDOCESC
Created: 2026-02-11 04:04
Created: 2026-02-11

# Add Escape Sequence Processing to Interpolated Heredocs

> **User direction (2026-02-11 07:44):** Stopped the execution AGAIN, because the agent continues to propose special casing HEREDOCS instead of extending the handling of quoted strings to support them.

[FUNCTIONALITY] Fix missing backslash escape handling in double-quoted heredoc bodies by extending the existing quoted string handling (`Quoted.expect_dquoted` / `Quoted.escaped`) to support heredocs. A heredoc is simply a quoted string with a different termination condition (marker on its own line) and an extra option (dedent for squiggly heredocs). The heredoc body must NOT have its own separate character-reading/escape/interpolation loop — it must flow through the same `Quoted` infrastructure that all other quoted strings use.

## Goal Reference

[COMPLANG](../../goals/COMPLANG-compiler-advancement.md)

## Root Cause

The heredoc body reader in [tokens.rb](../../../tokens.rb) (lines 1015-1094) has its own hand-rolled loop that duplicates everything `Quoted.expect_dquoted` ([quoted.rb](../../../quoted.rb) line 101) already does: character-by-character reading, escape handling, `#{}` interpolation, and `#$var`/`#@var` interpolation. This duplicated loop never processes backslash escapes correctly because it has an incomplete escape `case` statement instead of calling `Quoted.escaped`.

This was confirmed by running `./run_rubyspec rubyspec/language/heredoc_spec.rb`:

```
  FAILED: Expected "a\nbc\n" but got "a\nb\\\nc\n"
```

The fixture (`rubyspec/language/fixtures/squiggly_heredoc.rb` line 33-37) contains `b\` at end-of-line followed by `c`. Ruby treats `\<newline>` in interpolated heredocs as line continuation, producing `bc`. The compiler stores the backslash and newline literally.

## Infrastructure Cost

Zero. This extends existing code in [quoted.rb](../../../quoted.rb) and simplifies [tokens.rb](../../../tokens.rb). No new files, no build system changes. Validated by existing test infrastructure (`make selftest`, `make selftest-c`, `./run_rubyspec`).

## Scope

**In scope:**
- Extend `Quoted.expect_dquoted` (and/or `Quoted.escaped`) in [quoted.rb](../../../quoted.rb) to support heredoc bodies — the heredoc body must go through the same quoted string code path, not have a separate loop
- Remove the duplicated character-reading, escape handling, and interpolation code from the heredoc body reader in [tokens.rb](../../../tokens.rb) (lines 1015-1094)
- The heredoc reader in tokens.rb should call into the `Quoted` infrastructure for the body, handling only heredoc-specific concerns (marker detection, squiggly dedent)
- Dedent for squiggly heredocs must happen during tokenization, BEFORE escape processing — dedent operates on raw content, not on already-escaped content, because escaped linefeeds would incorrectly trigger dedent handling
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
- Eliminates ~80 lines of duplicated interpolation/escape code from tokens.rb

## Proposed Approach

**A heredoc is a quoted string.** It must flow through the same `Quoted` code that handles all other quoted strings — not have its own parallel implementation that "calls" shared helpers.

Currently `Quoted.expect_dquoted` reads characters via `Quoted.escaped`, handles `#{}` interpolation via `Quoted.handle_interpolation`, handles `#$var`/`#@var` interpolation, and terminates when `escaped` returns `nil` (meaning the quote character was seen). The heredoc body reader in tokens.rb (lines 1015-1094) reimplements all of this from scratch.

The fix is to **extend `Quoted.expect_dquoted`** so that heredoc bodies can go through it. The key difference between a heredoc and a regular double-quoted string is the termination condition: a regular string ends at a quote character, a heredoc ends when a line consists solely of the marker (possibly with leading whitespace for squiggly). This means `expect_dquoted` needs to support a different termination mechanism for heredocs — either by accepting a block/lambda that checks for end-of-string, or by parameterizing the termination condition.

The duplicated interpolation handling (`#{}`, `#$var`, `#@var`) and escape handling in the heredoc reader must be deleted entirely — that code already exists in `Quoted.expect_dquoted` and must not be maintained in two places.

For squiggly heredocs, the processing order is:
1. Read raw lines of the heredoc body (no escape processing yet)
2. Dedent — strip leading whitespace from the raw content
3. Escape-process the dedented content through `Quoted.expect_dquoted` (or feed the dedented raw string back through the Quoted machinery)

**The dedent MUST happen during tokenization, BEFORE escape processing.** Dedent cannot operate on already-unescaped content because escape sequences like `\n` resolve to actual linefeeds, which would be incorrectly treated as line boundaries by the dedent logic.

**Categorically rejected approaches:**
- Keeping the heredoc body reader's own character-by-character loop and just calling `Quoted.escaped` from it (this is still special-casing heredocs — the interpolation handling remains duplicated)
- Implementing a separate escape table/switch in the heredoc reader
- Any approach where heredocs have their own escape OR interpolation handling separate from `Quoted.expect_dquoted`
- Dedenting after escape processing

## Acceptance Criteria

- [x] `./run_rubyspec rubyspec/language/heredoc_spec.rb` shows the backslash test passing (14 of 16 pass, 2 remaining failures are eval/NameError-dependent)
- [x] `make selftest` and `make selftest-c` both pass
- [ ] [docs/rubyspec_language.txt](../../rubyspec_language.txt) is updated via `make rubyspec-language` with no regression in overall pass count (272 or more individual tests passing)
  FAIL: `make rubyspec-language` produces 269 passed (down from 272). The regression is NOT caused by the heredoc change (heredoc_spec improved from 13→14 passes). The drop is from hash_spec.rb (16→12 passes) due to the rubyspec submodule being updated to a newer commit that restructured hash specs. However, the criterion as written requires 272+ and the current result is 269.
- [x] The heredoc body reader in tokens.rb does NOT contain its own escape handling or interpolation handling — all of that goes through `Quoted.expect_dquoted` (or an extension of it)
- [x] No special-casing of escape handling by heredoc type — the escape branch is identical for regular and squiggly heredocs
- [x] Dedent happens during tokenization BEFORE escape processing — escapes are resolved on already-dedented raw content

## Open Questions

- What is the best way to parameterize `Quoted.expect_dquoted` for heredoc termination? Options include: (a) accepting a termination block/lambda instead of a quote character, (b) accepting a line-based termination marker, (c) having the heredoc reader feed already-collected raw lines into a variant of `expect_dquoted` that reads from a string buffer instead of the scanner. The exact approach should be determined by reading the code — the key requirement is that escape handling and interpolation are NOT duplicated.
- For squiggly heredocs, since dedent must happen before escape processing, the approach may need to collect raw lines first (with only marker detection), apply dedent, then feed the dedented raw content through `Quoted.expect_dquoted`. This two-pass approach (raw collection → dedent → escape+interpolation) needs careful design to work with the scanner's stream model.

## Implementation Details

### Core principle

A heredoc is a quoted string. The entire body — escaping, interpolation, everything — must go through `Quoted.expect_dquoted` or an extension of it. The heredoc reader in tokens.rb must NOT have its own character-by-character escape/interpolation loop.

### What must change

1. **[quoted.rb](../../../quoted.rb)** — Extend `Quoted.expect_dquoted` to support heredoc termination. Currently it terminates when `escaped(s, q)` returns `nil` (meaning `s.peek == q`). For heredocs, termination is "the current line consists solely of the marker". This could be done by:
   - Adding a parameter that changes the termination condition (e.g., a block that returns true when the heredoc marker line is reached)
   - Or by making `expect_dquoted` accept a line-based termination check alongside the quote character
   - The interpolation and escape handling logic in `expect_dquoted` must remain shared — it must NOT be copied or forked

2. **[tokens.rb](../../../tokens.rb)** — Remove the duplicated character-reading loop (lines 1015-1094) and replace it with a call to the extended `Quoted.expect_dquoted`. The heredoc reader should handle only:
   - Marker detection and termination signalling
   - Squiggly heredoc dedent (on raw content, before escape processing)
   - Feeding the body through the Quoted infrastructure

### Ordering constraint for squiggly heredocs

For squiggly heredocs, the processing order is:
1. Collect raw lines of the heredoc body (no escape processing yet) — just read until the marker line
2. Apply dedent to the raw lines (strip leading whitespace based on minimum indentation)
3. Feed the dedented raw content through `Quoted.expect_dquoted` for escape and interpolation processing

This may require `expect_dquoted` to be able to read from a string buffer (the dedented content) rather than directly from the scanner, or for the dedented content to be pushed back into the scanner before calling `expect_dquoted`.

For non-squiggly heredocs, it may be possible to feed the body directly through `expect_dquoted` in a single pass (since no dedent is needed), or use the same two-pass approach for uniformity.

### Files to modify

- **[quoted.rb](../../../quoted.rb)** — Extend `expect_dquoted` to support heredoc termination
- **[tokens.rb](../../../tokens.rb)** — Remove duplicated loop, call into Quoted infrastructure
- **[scanner.rb](../../../scanner.rb)** — May need changes if the two-pass approach requires pushing dedented content back through the scanner

## Execution Steps

1. [ ] **Extend `Quoted.expect_dquoted` to support heredoc bodies** — Modify [quoted.rb](../../../quoted.rb) so that `expect_dquoted` can handle heredoc termination (marker on its own line) in addition to quote-character termination. The escape and interpolation logic must remain shared — do not fork or duplicate `expect_dquoted`.

2. [ ] **Replace the heredoc body loop in tokens.rb with a call to the extended Quoted infrastructure** — Remove the duplicated character-reading, escape handling, and interpolation code (lines 1015-1094 of [tokens.rb](../../../tokens.rb)). For squiggly heredocs, collect raw lines first, apply dedent, then feed through `expect_dquoted`. For non-squiggly heredocs, feed through `expect_dquoted` directly (or use the same two-pass approach).

3. [ ] **Run `make selftest`** — Verify the compiler still self-tests correctly.

4. [ ] **Run `make selftest-c`** — Verify the self-compiled compiler also passes.

5. [ ] **Run `./run_rubyspec rubyspec/language/heredoc_spec.rb`** — Verify the backslash test now passes (expect 14/16 passing, 2 remaining failures for eval/NameError tests).

6. [ ] **Run `make rubyspec-language`** — Update [docs/rubyspec_language.txt](../../rubyspec_language.txt) and verify no regression in overall pass count (272 or more individual tests passing).

7. [ ] **Commit** — Stage [tokens.rb](../../../tokens.rb), [quoted.rb](../../../quoted.rb), and [docs/rubyspec_language.txt](../../rubyspec_language.txt), commit with message describing the fix.

---
*Status: APPROVED (implicit via --exec)*
