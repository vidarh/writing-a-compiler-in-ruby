HEREDOCESC
Created: 2026-02-11 04:04
Created: 2026-02-11

# Add Escape Sequence Processing to Interpolated Heredocs

> **User direction (2026-02-11 09:53):** This implementation continues to use an explicitly rejected approach of first reading the heredoc out and *then* call into quoted. This will *NEVER* be approved.

> **User direction (2026-02-11 08:49):** What the absolute fuck is this crap? Unget is for *actually ungetting unmodified tokens retrieved from the scanner.* Any change that pushes back *modified buffers* onto the scanner will be categorically rejected. This version completely ignored the direction from the previous pass, and implemented separate heredoc handling instead of augmenting quoted as directed.

> **User direction (2026-02-11 07:44):** Stopped the execution AGAIN, because the agent continues to propose special casing HEREDOCS instead of extending the handling of quoted strings to support them.
>
> **User direction (2026-02-11 08:49):** Unget is for *actually ungetting unmodified tokens retrieved from the scanner.* Any change that pushes back *modified buffers* onto the scanner will be categorically rejected. The implementation AGAIN implemented separate heredoc handling instead of augmenting quoted as directed.

> **User direction (2026-02-11 09:53):** The implementation continues to use an explicitly rejected approach of first reading the heredoc out and *then* calling into quoted. This will *NEVER* be approved.

[FUNCTIONALITY] Fix missing backslash escape handling in double-quoted heredoc bodies by extending the existing quoted string handling (`Quoted.expect_dquoted` / `Quoted.escaped`) to support heredocs. A heredoc is simply a quoted string with a different termination condition (marker on its own line) and an extra option (dedent for squiggly heredocs). The heredoc body must NOT be pre-read into a buffer and then fed to Quoted — `Quoted.expect_dquoted` must read the heredoc body directly from the scanner, character by character, exactly as it does for regular double-quoted strings.

## Goal Reference

[COMPLANG](../../goals/COMPLANG-compiler-advancement.md)

## Root Cause

The heredoc body reader in [tokens.rb](../../../tokens.rb) has its own hand-rolled loop that duplicates everything `Quoted.expect_dquoted` ([quoted.rb](../../../quoted.rb) line 119) already does: character-by-character reading, escape handling, `#{}` interpolation, and `#$var`/`#@var` interpolation.

This was confirmed by running `./run_rubyspec rubyspec/language/heredoc_spec.rb`:

```
  FAILED: Expected "a\nbc\n" but got "a\nb\\\nc\n"
```

The fixture (`rubyspec/language/fixtures/squiggly_heredoc.rb` line 33-37) contains `b\` at end-of-line followed by `c`. Ruby treats `\<newline>` in interpolated heredocs as line continuation, producing `bc`. The compiler stores the backslash and newline literally.

## Infrastructure Cost

Zero. This extends existing code in [quoted.rb](../../../quoted.rb) and simplifies [tokens.rb](../../../tokens.rb). No new files, no build system changes. Validated by existing test infrastructure (`make selftest`, `make selftest-c`, `./run_rubyspec`).

## Scope

**In scope:**
- Extend `Quoted.expect_dquoted` (and/or `Quoted.escaped`) in [quoted.rb](../../../quoted.rb) to support heredoc bodies — `expect_dquoted` must read the heredoc body directly from the scanner, not from a pre-read buffer
- Remove the duplicated character-reading, escape handling, and interpolation code from the heredoc body reader in [tokens.rb](../../../tokens.rb)
- The heredoc reader in tokens.rb should call `Quoted.expect_dquoted` with a termination condition that detects the heredoc marker, and `expect_dquoted` reads directly from the scanner
- For squiggly heredocs, dedent must be handled as part of the reading process — the termination callback or `expect_dquoted` augmentation must handle marker detection with leading-whitespace stripping, and indentation removal must be integrated into the reading flow rather than applied as a post-processing pass on a pre-read buffer
- Validate with `make selftest`, `make selftest-c`, and `./run_rubyspec rubyspec/language/heredoc_spec.rb`
- Update [docs/rubyspec_language.txt](../../rubyspec_language.txt) via `make rubyspec-language`

**Out of scope:**
- Escape handling in single-quoted heredocs (Ruby does not process escapes there, except `\\` and `\'`)
- Fixing the other two heredoc_spec failures (one requires `eval`, one requires `NameError`)

## Expected Payoff

- heredoc_spec.rb failure count drops from 3 to 2 (the backslash test passes; the remaining 2 require eval/NameError)
- Heredocs containing `\n`, `\t`, `\\`, or line continuations now work correctly throughout the compiler
- Advances individual test pass rate
- May fix failures in other spec files that use escape sequences inside heredocs (e.g., string_spec.rb has 14 failures)
- Eliminates duplicated interpolation/escape code from tokens.rb

## Proposed Approach

**A heredoc is a quoted string.** `Quoted.expect_dquoted` must read the heredoc body directly from the scanner — exactly as it reads any other double-quoted string. The ONLY difference is the termination condition: instead of stopping at a quote character, it stops when a line consists solely of the heredoc marker (possibly with leading whitespace for squiggly).

**The heredoc body must NOT be pre-read into a buffer and then fed to Quoted.** This "read first, process second" approach has been attempted multiple times and is categorically rejected. `expect_dquoted` must consume the heredoc body from the scanner in real time, processing escapes and interpolation as it goes — the same way it handles `"..."` strings.

The fix is to **augment `Quoted.expect_dquoted`** with a termination callback (or equivalent mechanism) that checks for the heredoc end marker at line boundaries. The termination callback receives the scanner and returns true when the marker line is detected. The existing `escaped` method already supports a `term` parameter for this purpose.

The termination callback for heredocs must:
- At each newline boundary, peek ahead to check if the next line is the marker
- For squiggly heredocs, strip leading whitespace before comparing to the marker
- Consume the marker line when found (or signal `expect_dquoted` to stop before it)

For squiggly heredoc dedent: Ruby's `<<~` dedent strips leading whitespace from each line based on the minimum indentation of non-blank lines. This is a challenge when reading directly from the scanner because the minimum indentation isn't known until the entire body has been seen. Possible approaches:
- The termination callback can track indentation of each line as they are read, and `expect_dquoted` can be augmented to support a post-processing step that applies dedent to the already-processed result
- Or the dedent can be deferred to a post-processing step on the token result, since dedent operates on the content level (removing leading whitespace characters) rather than the escape level
- The key constraint is that the body is read from the scanner by `Quoted.expect_dquoted` in a single pass — NOT pre-read into a buffer

**Note on squiggly dedent ordering:** In the rejected two-pass approach, dedent was applied to raw content before escape processing. When reading directly from the scanner, the implementation must find an alternative way to handle dedent correctly. The important semantic is that `\n` inside a heredoc should resolve to a newline, and leading whitespace on source lines (not on lines created by escape sequences) should be stripped. Since escape sequences like `\n` in source produce a single newline character (not a source-level line break followed by indented content), dedent on the output should produce correct results in practice.

**Categorically rejected approaches:**
- **Pre-reading the heredoc body into a buffer and then feeding it to Quoted** — this "read first, process second" approach will NEVER be approved. `expect_dquoted` must read directly from the scanner.
- Keeping the heredoc body reader's own character-by-character loop and just calling `Quoted.escaped` from it (this is still special-casing heredocs — the interpolation handling remains duplicated)
- Implementing a separate escape table/switch in the heredoc reader
- Any approach where heredocs have their own escape OR interpolation handling separate from `Quoted.expect_dquoted`
- **Pushing modified buffers back onto the scanner via unget** — `unget` is for ungetting unmodified tokens retrieved from the scanner, NOT for injecting modified/constructed content
- Any approach that implements separate heredoc handling instead of augmenting the existing `Quoted` infrastructure
- **Using `BufferedScanner` or any similar wrapper to feed pre-read content through `Quoted`** — this is just the rejected "read first, process second" approach with an extra layer of indirection

## Acceptance Criteria

- [ ] `./run_rubyspec rubyspec/language/heredoc_spec.rb` shows the backslash test passing (14 of 16 pass, 2 remaining failures are eval/NameError-dependent)
- [ ] `make selftest` and `make selftest-c` both pass
- [ ] [docs/rubyspec_language.txt](../../rubyspec_language.txt) is updated via `make rubyspec-language` with no regression in overall pass count
- [ ] The heredoc body reader in tokens.rb does NOT contain its own escape handling or interpolation handling — all of that goes through `Quoted.expect_dquoted` (or an extension of it)
- [ ] `Quoted.expect_dquoted` reads the heredoc body directly from the scanner — the body is NOT pre-read into a buffer and then fed to Quoted
- [ ] No special-casing of escape handling by heredoc type — the escape branch is identical for regular and squiggly heredocs
- [ ] No use of `unget` or any scanner pushback mechanism for modified/constructed buffers — only unmodified tokens retrieved from the scanner may be ungotten
- [ ] No `BufferedScanner` or equivalent wrapper — `Quoted.expect_dquoted` reads from the real scanner

## Open Questions

- How should squiggly heredoc dedent work when `expect_dquoted` reads directly from the scanner? The minimum indentation isn't known until the entire body has been seen, but the body is being consumed and escape-processed in a single pass. Options: (a) dedent as a post-processing step on the token result (strip leading whitespace from each line of the processed string), (b) have the termination callback track line indentation and pass the min back for post-processing, (c) two-pass at a higher level (first scan to find min indent without consuming, then process through `expect_dquoted` with indent stripping integrated into the termination/reading logic). The exact approach should be determined by reading the code — the key requirement is that `expect_dquoted` reads from the scanner, not from a pre-read buffer.

## Implementation Details

### Core principle

A heredoc is a quoted string. `Quoted.expect_dquoted` must read the heredoc body directly from the scanner, processing escapes and interpolation as it goes. The heredoc reader in tokens.rb calls `expect_dquoted` with a termination condition and `expect_dquoted` does the rest. The body is NOT pre-read.

### What must change

1. **[quoted.rb](../../../quoted.rb)** — Augment `Quoted.expect_dquoted` (and/or `Quoted.escaped`) to support heredoc termination. The `escaped` method already accepts a `term` block parameter. The termination callback for heredocs must detect when the next line is the marker. This may require the callback to peek ahead at line boundaries, checking if the upcoming line matches the marker (with optional leading whitespace for squiggly). The escape and interpolation handling in `expect_dquoted` remains shared and unchanged.

2. **[tokens.rb](../../../tokens.rb)** — Remove the duplicated character-reading loop and replace it with a call to `Quoted.expect_dquoted` with a heredoc termination callback. The heredoc reader should:
   - Construct a termination callback that detects the marker line
   - Call `Quoted.expect_dquoted(scanner, nil, term_callback) { parse_defexp }` and let Quoted read directly from the scanner
   - Handle squiggly dedent (possibly as post-processing on the result)
   - Handle `rest_of_line` ungetting (this is legitimate — it's unmodified content read from the scanner)

### Squiggly heredoc dedent

The challenge with squiggly heredocs is that dedent requires knowing the minimum indentation, which isn't available until the entire body is read. Since the approach must NOT pre-read the body, possible strategies include:
- Post-process the result returned by `expect_dquoted` to apply dedent (strip leading whitespace from each line based on minimum indentation). This works on the processed string content and is simpler than trying to integrate dedent into the reading pass.
- Have the termination callback accumulate indentation data as lines pass through, then apply dedent afterward.

The exact approach should be determined during implementation. The constraint is: `expect_dquoted` reads from the scanner, not from a buffer.

### Files to modify

- **[quoted.rb](../../../quoted.rb)** — Augment `expect_dquoted`/`escaped` to support heredoc termination directly from the scanner
- **[tokens.rb](../../../tokens.rb)** — Remove duplicated loop, call `expect_dquoted` with heredoc termination callback

## Execution Steps

1. [ ] **Augment `Quoted.expect_dquoted` to support heredoc bodies reading directly from the scanner** — Modify [quoted.rb](../../../quoted.rb) so that `expect_dquoted` can handle heredoc termination (marker on its own line) using the termination callback mechanism. `expect_dquoted` reads character-by-character from the scanner just as it does for regular strings. Do NOT pre-read the body into a buffer.

2. [ ] **Replace the heredoc body loop in tokens.rb with a call to `Quoted.expect_dquoted`** — Remove the duplicated character-reading, escape handling, and interpolation code from [tokens.rb](../../../tokens.rb). The heredoc reader constructs a termination callback and calls `expect_dquoted` directly. For squiggly heredocs, apply dedent as post-processing or via another appropriate mechanism that does not require pre-reading the body.

3. [ ] **Run `make selftest`** — Verify the compiler still self-tests correctly.

4. [ ] **Run `make selftest-c`** — Verify the self-compiled compiler also passes.

5. [ ] **Run `./run_rubyspec rubyspec/language/heredoc_spec.rb`** — Verify the backslash test now passes (expect 14/16 passing, 2 remaining failures for eval/NameError tests).

6. [ ] **Run `make rubyspec-language`** — Update [docs/rubyspec_language.txt](../../rubyspec_language.txt) and verify no regression in overall pass count.

7. [ ] **Commit** — Stage [tokens.rb](../../../tokens.rb), [quoted.rb](../../../quoted.rb), and [docs/rubyspec_language.txt](../../rubyspec_language.txt), commit with message describing the fix.

---
*Status: APPROVED (implicit via --exec)*
