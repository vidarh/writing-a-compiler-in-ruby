# HEREDOCESC Test Specification

## Test Suite Location

All new tests go in `spec/heredoc_escape_spec.rb`, using the project's mspec format. This file is run via `./run_rubyspec spec/heredoc_escape_spec.rb` or as part of `make spec`.

The existing rubyspec suite (`rubyspec/language/heredoc_spec.rb`) serves as the primary acceptance gate — it must NOT be edited. It is run via `./run_rubyspec rubyspec/language/heredoc_spec.rb`.

## Design Requirements

No refactoring is needed for testability. The change is entirely within the tokenizer's heredoc body reader. Testing is end-to-end: compile a Ruby source containing a heredoc, run it, check the output string. This is how all specs work in this project — there is no unit-test-level access to the tokenizer in isolation, and adding one is out of scope.

All tests are self-contained mspec files that the compiler compiles and executes. No mocking infrastructure exists or is needed — the tests exercise the compiler's own output directly.

## Required Test Coverage

### Happy Path — Basic Escape Sequences

1. **`\n` in heredoc body produces LF**
   ```ruby
   s = <<HERE
   a\nb
   HERE
   s.should == "a\nb\n"
   ```
   Verify that `\n` inside an interpolated heredoc becomes a newline character, not the two characters `\` and `n`.

2. **`\t` in heredoc body produces TAB**
   ```ruby
   s = <<HERE
   a\tb
   HERE
   s.should == "a\tb\n"
   ```

3. **`\\` in heredoc body produces single backslash**
   ```ruby
   s = <<HERE
   a\\b
   HERE
   s.should == "a\\b\n"
   ```
   The two-character sequence `\\` must collapse to one `\`.

4. **`\e` in heredoc body produces ESC (0x1B)**
   ```ruby
   s = <<HERE
   \e[31m
   HERE
   s.should == "\e[31m\n"
   ```

5. **Line continuation (`\<newline>`) joins lines**
   ```ruby
   s = <<HERE
   ab\
   cd
   HERE
   s.should == "abcd\n"
   ```
   A backslash immediately before a newline absorbs both characters, joining the two lines.

### Happy Path — Interaction with Interpolation

6. **`\#` prevents interpolation**
   ```ruby
   x = "nope"
   s = <<HERE
   \#{x}
   HERE
   s.should == "\#{x}\n"
   ```
   The `\#` sequence must produce a literal `#` that is NOT treated as the start of interpolation.

7. **Escape sequences coexist with interpolation**
   ```ruby
   val = "world"
   s = <<HERE
   hello\t#{val}\n
   HERE
   s.should == "hello\tworld\n\n"
   ```
   Both `\t`, interpolation, and `\n` must be resolved correctly in the same heredoc.

### Happy Path — Single-Quoted Heredocs Are Unaffected

8. **Single-quoted heredoc preserves backslashes literally**
   ```ruby
   s = <<'HERE'
   a\nb\tc\\d
   HERE
   s.should == "a\\nb\\tc\\\\d\n"
   ```
   Escape sequences must NOT be processed when the heredoc is single-quoted.

### Happy Path — Squiggly Heredocs

9. **`<<~` heredoc with line continuation**
   This is the rubyspec acceptance case. Do not duplicate it — just reference it:
   - `./run_rubyspec rubyspec/language/heredoc_spec.rb` must show the "allows HEREDOC with <<~'identifier', no interpolation, with backslash" test passing.

   Additionally, add a custom spec to cover `<<~` with `\n`:
   ```ruby
   s = <<~HERE
     a\nb
   HERE
   s.should == "a\nb\n"
   ```

### Edge Cases

10. **Backslash at end of heredoc body (before marker line)**
    ```ruby
    s = <<HERE
    trail\\
    HERE
    s.should == "trail\\\n"
    ```
    Wait — with line continuation, `\<newline>` should join with the next line. But the next line is the marker. This tests that the marker is still recognized after line continuation consumes the newline. The expected behavior: `\` followed by newline is line continuation; the next line (`HERE`) becomes part of the continued line content, which means the marker won't be found on its own line. **This is intentionally tricky** — Ruby's actual behavior is that `\<newline>` before a marker line causes the marker to not be recognized, making the heredoc unterminated. The test should verify that `\\` (double backslash, producing single backslash) before a newline does NOT trigger line continuation:
    ```ruby
    s = <<HERE
    trail\\
    HERE
    s.should == "trail\\\n"
    ```
    (`\\` → single `\`, then normal newline, then marker is recognized.)

11. **Unknown escape sequence passes through**
    ```ruby
    s = <<HERE
    \q\z
    HERE
    ```
    The behavior should match the compiler's existing double-quoted string handling (via `Quoted.escaped`). Unknown escapes produce just the character after the backslash (i.e., `\q` → `q`). Verify:
    ```ruby
    s.should == "qz\n"
    ```

12. **Backslash before EOF / missing terminator**
    Not directly testable as a passing spec (it would be a parse error), but ensure that a lone backslash as the very last character before the marker does not crash the compiler. This is covered implicitly by test 10.

13. **Multiple consecutive escape sequences**
    ```ruby
    s = <<HERE
    \t\t\n\\
    HERE
    s.should == "\t\t\n\\\n"
    ```

14. **`\r` in heredoc body produces CR (0x0D)**
    ```ruby
    s = <<HERE
    a\rb
    HERE
    s.should == "a\rb\n"
    ```

### Regression Gate

15. **`make selftest` passes** — not a spec file, but the execution agent must run this.
16. **`make selftest-c` passes** — self-compiled compiler must also pass.
17. **`./run_rubyspec rubyspec/language/heredoc_spec.rb`** — expect 14/16 passing (up from 13/16).
18. **`make rubyspec-language`** — overall pass count must not regress below 272.

## Mocking Strategy

No mocking is needed. All tests are compiled-and-executed integration tests — the standard pattern for this project. The compiler compiles the spec file to a native binary, runs it, and mspec checks the assertions. There are no external services, network calls, or databases involved.

## Invocation

```bash
# Run the new custom spec:
./run_rubyspec spec/heredoc_escape_spec.rb

# Run the rubyspec acceptance gate:
./run_rubyspec rubyspec/language/heredoc_spec.rb

# Self-hosting validation (must pass):
make selftest
make selftest-c

# Full language spec update (must not regress):
make rubyspec-language
```

All commands exit non-zero on failure.

## Known Pitfalls

1. **Do NOT edit files in `rubyspec/`** — The rubyspec suite is read-only. The heredoc_spec.rb and squiggly_heredoc.rb fixtures must not be modified.

2. **Spec format is mspec, not plain Ruby** — Every test file must `require_relative '../rubyspec/spec_helper'` and use `describe`/`it`/`.should` syntax. Plain `puts`-and-compare scripts will not work with `./run_rubyspec`.

3. **String literal expectations need care** — When writing expected values in mspec, remember that the spec file itself is compiled by the compiler. If the compiler's double-quoted string handling already resolves `\n` to LF (it does, via `Quoted.escaped`), then `"a\nb\n"` in the expected value is already the correct two-line string. The test is checking that the *heredoc* produces the same bytes as the *string literal*.

4. **Line continuation changes line counting** — After implementing `\<newline>` support, the heredoc body reader consumes the newline inside the inner loop. Make sure tests verify that subsequent lines are still read correctly (test 5 covers this).

5. **`\\` vs `\<newline>` ambiguity** — `\\` followed by a newline should produce a single backslash and then a normal line break (the marker on the next line is still recognized). `\<newline>` (single backslash before newline) is line continuation. Test 10 specifically covers this distinction.

6. **Don't test `\0xx`, `\xNN`, `\uNNNN`** — These are explicitly out of scope per the plan. Don't add tests for octal, hex, or unicode escapes.

7. **Run `make selftest` before `make selftest-c`** — The self-compiled compiler (`selftest-c`) depends on the initial compiler build. Always validate the base build first.

8. **The `\r` escape (test 14) may not be verifiable on all platforms** — The mspec `.should ==` comparison works on byte values, so CR (0x0D) should compare correctly regardless of platform. But be aware that some terminal/output handling may swallow CR characters if debugging via `puts`.
