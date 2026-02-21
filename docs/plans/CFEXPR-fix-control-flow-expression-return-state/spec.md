CFEXPR
Created: 2026-02-21

# Fix Control Flow Expression Return State in Shunting Yard

[PARSARCH] Fix the shunting yard so that `if`, `while`, `unless`, `until`, and `for` expressions
in value position return `:infix_or_postfix` (matching the existing `begin_stmt` behavior), enabling
operators to be applied to their results — e.g., `if cond; 42; end.to_s`, `while c; x; end.nil?`,
`[1, if true; 2; end, 3]`.

## Goal Reference

[PARSARCH](../../goals/PARSARCH-parser-architecture.md)

Also advances [COMPLANG](../../goals/COMPLANG-compiler-advancement.md): the blocked language specs
`unless_spec`, `while_spec`, `symbol_spec`, `metaclass_spec` and others fail due to control flow not
being usable as expressions.

## Prior Plans

No prior plans exist in `docs/plans/` or `docs/plans/archived/` for PARSARCH. However,
[docs/control_flow_as_expressions.md](../../control_flow_as_expressions.md) documents three
prior fix attempts in sessions 45-46, each of which failed for a distinct reason:

- **Attempt 1: Add all keywords to `@escape_tokens`** — Failed. Too blunt, broke selftest in
  `lib/core/object.rb`. `@escape_tokens` causes the keyword to be consumed eagerly even at statement
  level, breaking statement-sequence body parsing.
  **This plan does NOT touch `@escape_tokens`.** The escape_token mechanism is the wrong tool here.

- **Attempt 2: Modify keyword stopping logic (`ostack.empty? && opstate == :prefix`)** — Failed
  with nested control structures parsing the wrong `end` tokens ("the while loop's shunting yard
  instance incorrectly tried to parse the `if` at line 330 as part of the while body").
  **Diagnosis**: Attempt 2 likely REMOVED the `opstate == :prefix` guard from the condition, which
  caused `if_mod` in `:infix_or_postfix` state to trigger the control-flow handler after a
  preceding value. This meant `while..end\nif cond` was parsed as a modifier, consuming `if`'s
  `end` and leaving the while's `end` orphaned. **This plan keeps the `opstate == :prefix` guard
  intact** — only the RETURN VALUE changes, not the entry condition.

- **Attempt 3: `parse_method_chain` hack** — Rejected as a partial fix (only method chaining, not
  arithmetic or array literals). Not relevant to this approach.

## Root Cause

The shunting yard already has code to parse control flow keywords as expression values when
encountered in prefix position. In [shunting.rb](../../shunting.rb):141-207 there is:

```ruby
# begin is always a complete expression that produces a value
if opstate == :prefix && op.sym == :begin_stmt
  @out.value(@parser.parse_begin_body)
  return :infix_or_postfix  # ← CORRECT: allows operators after begin..end
end

# When if/unless/while/until/rescue appear in prefix position...
if opstate == :prefix && (ostack.empty? || ostack.last.type != :prefix)
  if op.sym == :if_mod
    @out.value(@parser.parse_if_body(:if))
    return :prefix              # ← BUG: should be :infix_or_postfix
  elsif op.sym == :unless_mod
    @out.value(@parser.parse_if_body(:unless))
    return :prefix              # ← BUG: should be :infix_or_postfix
  elsif op.sym == :while_mod
    @out.value(@parser.parse_while_until_body(:while))
    return :prefix              # ← BUG: should be :infix_or_postfix
  elsif op.sym == :until_mod
    @out.value(@parser.parse_while_until_body(:until))
    return :prefix              # ← BUG: should be :infix_or_postfix
  elsif op.sym == :for_stmt
    @out.value(@parser.parse_for_body())
    return :prefix              # ← BUG: should be :infix_or_postfix
  end
end
```

The `:begin_stmt` handler returns `:infix_or_postfix` — correctly signaling "I just produced a
value, subsequent tokens can be operators." The five other control flow handlers return `:prefix`,
which means "I just processed a prefix operator, still looking for an operand." This incorrect
state prevents any operator (`.to_s`, `+ 1`, `[0]`, `.nil?`) from being applied to the control
flow result.

**Why the wrong return breaks things**: After `if true; 42; end`, the value `42` is on @out's
value stack. opstate is set to `:prefix` (wrong). The next token `.` is an infix operator. With
opstate=`:prefix`, the `oper()` function sees an infix operator where it expected a value —
depending on the specific operator and inhibit conditions, this either silently discards the `.`
or produces a parse error ("Method call requires two values, but only one was found"). Either way,
`if true; 42; end.to_s` fails.

**Why changing to `:infix_or_postfix` is safe** (addresses Attempt 2's failure):

The entry condition `opstate == :prefix && (ostack.empty? || ostack.last.type != :prefix)` is
PRESERVED. After `while...end` produces a result and opstate becomes `:infix_or_postfix`, the
condition is no longer satisfied — `opstate == :prefix` is now FALSE. So a following `if neg` on
a separate line cannot trigger the control flow handler and cannot be misinterpreted as a modifier.

The `\n` between statements is in parse_subexp's inhibit list. With opstate=`:infix_or_postfix`,
`\n` is an inhibited operator, so the shunting yard stops cleanly and returns the while-expression.
The next call to `parse_exp` handles `if neg` as a fresh statement.

**Reference**: `:begin_stmt` has been returning `:infix_or_postfix` correctly (line 146), and the
compiler's own code uses `begin...end` as expressions in some contexts. The same treatment should
apply to `if`, `while`, `unless`, `until`, and `for`.

## Infrastructure Cost

Zero. This changes 5 return values in a single file ([shunting.rb](../../shunting.rb)) from
`:prefix` to `:infix_or_postfix`. No new files, no build system changes, no new dependencies.
Validation uses existing `make selftest`, `make selftest-c`, and `./run_rubyspec` commands.

## Scope

**In scope:**

1. In [shunting.rb](../../shunting.rb), change `return :prefix` to `return :infix_or_postfix` for:
   - `op.sym == :if_mod` handler (parse_if_body(:if))
   - `op.sym == :unless_mod` handler (parse_if_body(:unless))
   - `op.sym == :while_mod` handler (parse_while_until_body(:while))
   - `op.sym == :until_mod` handler (parse_while_until_body(:until))
   - `op.sym == :for_stmt` handler (parse_for_body())

2. Run `make selftest` and `make selftest-c` (regression gate).

3. Run all existing control flow expression spec files in `spec/`:
   - [spec/control_flow_expressions_spec.rb](../../spec/control_flow_expressions_spec.rb) (7 tests)
   - [spec/all_control_flow_end_should_spec.rb](../../spec/all_control_flow_end_should_spec.rb) (4 tests)
   - [spec/while_end_chain_spec.rb](../../spec/while_end_chain_spec.rb) (2 tests)
   - [spec/while_end_no_paren_spec.rb](../../spec/while_end_no_paren_spec.rb) (1 test)
   - [spec/if_end_should_spec.rb](../../spec/if_end_should_spec.rb) (if it exists)
   - [spec/unless_end_should_spec.rb](../../spec/unless_end_should_spec.rb) (if it exists)

4. Run `./run_rubyspec rubyspec/language/unless_spec.rb` and
   `./run_rubyspec rubyspec/language/while_spec.rb` to measure direct impact.

5. Update [docs/control_flow_as_expressions.md](../../control_flow_as_expressions.md) to reflect
   current state (this document references parser.rb line numbers that have shifted significantly
   since sessions 45-46 — the document says "parser.rb:484" for parse_defexp but the current file
   has it at line 788).

**Optionally in scope** (if the above succeeds cleanly):

6. Check `op.sym == :class_stmt` (line 200) and `op.sym == :module_stmt` (line 204) — these
   also return `:prefix`. For consistency with `begin_stmt`, they should probably return
   `:infix_or_postfix` too, though class/module definitions chained with operators is unusual Ruby.

**Out of scope:**

- Fixing the `for` expression semantics (Ruby's `for` returns the enumerable, not the body).
- Investigating `parse_defexp` restructuring or removing control flow from the statement-level
  parser — this is the deeper PARSARCH architectural goal. This plan is the minimal fix that
  enables control flow as expressions without architectural changes.
- Fixing `rescue` modifier behavior (line 172-179 handles this separately with a `break`).

## Expected Payoff

**Direct spec fixes:**

- `spec/control_flow_expressions_spec.rb`:
  - "supports if with method chaining" (test 3): `if true; 42; end.to_s` — passes
  - "supports if in array literals" (test 5): `[1, if true; 2; end, 3]` — passes
  - "supports arithmetic with if result" (test 6): `(if true; 10; end) + 5` — passes
- `spec/all_control_flow_end_should_spec.rb`: all 4 tests pass (`if end.should`, `unless end.should`,
  `while end.should`, `until end.should`)
- `spec/while_end_no_paren_spec.rb`: passes (while without parens + method chain)
- `spec/while_end_chain_spec.rb`: passes (while/until with parens + method chain)

**Language spec improvement:**

- `rubyspec/language/unless_spec.rb`: tests that use `unless...end.should` pattern
- `rubyspec/language/while_spec.rb`: tests that use while return value
- Other language specs that test control flow in expression contexts

**Downstream (PARSARCH / COMPLANG):**

- The fix is the first step toward the PARSARCH architectural goal of full "control flow as
  expressions" support. While this change is minimal (return value only), it may unlock a
  surprising number of spec improvements since `if...end.should` is a common rubyspec pattern.

## Proposed Approach

**Step 1: Validate current state** — Before changing anything, run the existing spec files to
confirm which currently fail. This establishes the baseline.

**Step 2: Make the change** — In [shunting.rb](../../shunting.rb), in the `oper()` method, find
the block at approximately line 149-207 where `if_mod`, `unless_mod`, `while_mod`, `until_mod`,
and `for_stmt` are handled. Change their return statements from `return :prefix` to
`return :infix_or_postfix`.

The exact change (5 lines total):
```
- return :prefix   # after parse_if_body(:if)
+ return :infix_or_postfix
- return :prefix   # after parse_if_body(:unless)
+ return :infix_or_postfix
- return :prefix   # after parse_while_until_body(:while)
+ return :infix_or_postfix
- return :prefix   # after parse_while_until_body(:until)
+ return :infix_or_postfix
- return :prefix   # after parse_for_body()
+ return :infix_or_postfix
```

**Step 3: Run selftest** — `make selftest` is the regression gate. If it fails, the fix caused
a regression. Investigate the specific failure and determine whether it's the Attempt 2 failure
pattern (nested structure issue) or something else. Do NOT revert without investigation.

**Step 4: Run selftest-c** — `make selftest-c` validates self-hosting. If selftest passes but
selftest-c fails, there is a self-hosting regression introduced by the change.

**Step 5: Run the spec files** — Run all control flow expression spec files listed in the Scope
section to measure improvement.

**Step 6: Run language specs** — Run `rubyspec/language/unless_spec.rb` and
`rubyspec/language/while_spec.rb`.

**Step 7: Update documentation** — Update
[docs/control_flow_as_expressions.md](../../control_flow_as_expressions.md) with current state
(passing/failing test counts, updated line number references, new status).

## Acceptance Criteria

- [ ] [shunting.rb](../../shunting.rb) control flow handlers return `:infix_or_postfix` for
  `if_mod`, `unless_mod`, `while_mod`, `until_mod`, `for_stmt` (verified by reading the file)

- [ ] `make selftest` passes (no regression)

- [ ] `make selftest-c` passes (no self-hosting regression)

- [ ] `spec/control_flow_expressions_spec.rb` test "supports if with method chaining" passes:
  `def test_if_to_s; if true; 42; end.to_s; end; test_if_to_s.should == "42"`

- [ ] `spec/all_control_flow_end_should_spec.rb` all 4 tests pass:
  `if true; 42; end.should == 42` (and unless/while/until variants)

- [ ] `spec/while_end_no_paren_spec.rb` passes:
  `while i < 3; i = i + 1; end.should == nil`

- [ ] [docs/control_flow_as_expressions.md](../../control_flow_as_expressions.md) is updated with
  current pass/fail status and current parser line number references

## Open Questions

- Does the `op.sym == :lambda_stmt` handler at line 180 also need `:infix_or_postfix`? It
  returns `:prefix` after parsing a lambda block. In standard Ruby, `lambda { }.call` works.
  If this is broken, it should be fixed too (same pattern), but this should be tested first.

- Does `class_stmt` / `module_stmt` (lines 198-205) need the same fix? These return `:prefix`.
  Chaining on class/module definitions is unusual but valid Ruby. If the selftests pass with
  those changed, it's a consistent improvement.

- Are there any places in the compiler's own source (`lib/core/`) where control flow expressions
  are used in method-chain position that currently work via workaround? If so, those workarounds
  can be removed after this fix.

---
*Status: PROPOSAL*
