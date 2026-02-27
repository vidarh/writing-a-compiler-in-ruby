TERNPREC
Created: 2026-02-27

# Fix Ternary `?:` Operator Precedence Relative to `||`

[SELFHOST] Fix `operators.rb` so that the ternary `?` operator has lower precedence than `||`,
making `a || b ? c : d` parse as `(a || b) ? c : d` (Ruby-correct) instead of `a || (b ? c : d)`
(current wrong behavior), and remove the two confirmed `@bug` workarounds in `treeoutput.rb`.

## Goal Reference

[SELFHOST](../../goals/SELFHOST-clean-bootstrap.md)

## Prior Plans

No prior plans in `docs/plans/` or `docs/plans/archived/` target ternary operator precedence or the
`ternif` operator definition. The BUGAUDIT plan (IMPLEMENTED, archived) documented this as **Cat 3
Bug** with markers 13 and 14, confirmed the bug with `spec/bug_ternary_expression_spec.rb` (6 pass,
1 fail), and explicitly excluded fixing it: "Out of scope: Fixing confirmed bugs (that is separate
plan work under SELFHOST or COMPLANG)." ENVFIX (active) explicitly excludes "non-collision @bug
categories (yield in nested blocks, ternary, block_given?, break register corruption)." No plan has
ever attempted to fix this.

## Root Cause

In `operators.rb`, the `?` (ternary if) and `||` operators share the same priority value:

```ruby
"?"         => Oper.new(  6, :ternif,   :infix),   # priority 6
"||"        => Oper.new(  6, :or,       :infix),   # priority 6 — same!
```

The file header notes: "LARGER numbers mean TIGHTER binding (higher precedence)." In standard
Ruby, `||` has **higher** precedence than `?:`, meaning `a || b ? c : d` parses as
`(a || b) ? c : d`. With both operators at priority 6, the shunting yard uses associativity
to break the tie: both are right-associative, so when `?` arrives with `||` on the stack at equal
priority, the algorithm does NOT reduce `||` first (right-assoc equal-priority → push without
reducing). This produces the wrong parse: `a || (b ? c : d)`.

**Observed symptom** (from `spec/bug_ternary_expression_spec.rb`, line 12-17):
```ruby
comma = true
block = false
result = comma || block ? "yes" : "no"
result.should == "yes"   # FAILS: returns `true` instead of "yes"
```

When parsed as `true || (false ? "yes" : "no")` = `true || "no"` = `true` (short-circuit returns
`true` directly). Correct parse `(true || false) ? "yes" : "no"` = `true ? "yes" : "no"` = `"yes"`.

The `operators.rb` file's FIXME (line 68) acknowledges: "Currently the priorities and
associativity etc. have not been systematically validated." This is exactly such a validation gap.

**Affected treeoutput.rb workarounds** (from BUGAUDIT markers 13-14):

- **[treeoutput.rb:235](../../treeoutput.rb)** — `args = comma || block ? flatten(rightv) : rightv`
  was replaced by an explicit `if`/`elsif`/`else` chain because this exact expression evaluates
  incorrectly in the self-hosted compiler.

- **[treeoutput.rb:262](../../treeoutput.rb)** — `args = lv ? lv + rightv : rightv` was replaced
  by an `if/else` because "putting the above as a ternary if causes selftest-c target to fail."
  This may be a secondary effect of the same precedence issue (or a related ternary compilation
  bug in the self-hosted compiler).

## Infrastructure Cost

Low. The primary change is a single constant in [`operators.rb`](../../operators.rb) (line 126).
The risk surface is the shunting yard in [`shunting.rb`](../../shunting.rb) and the ternary
compiler in [`compiler.rb`](../../compiler.rb):514. Validation uses existing `make selftest`,
`make selftest-c`, and `./run_rubyspec`. No new files, no build system changes.

**The main risk** is that lowering `?`'s priority interacts unexpectedly with `:` (ternalt at
priority 7) or assignment operators (priority 7, right_pri 5). Investigation must verify these
interactions before committing to a specific priority value.

## Scope

**In scope:**

1. **Determine the correct priority for `?`** that satisfies all constraints:
   - Lower than `||` (pri=6) so `a || b ? c : d` parses as `(a || b) ? c : d`
   - Compatible with `:` (pri=7) so `b ? c : d` still produces `[:ternif, b, [:ternalt, c, d]]`
   - Compatible with `=` (pri=7, right_pri=5) so `a = b ? c : d` parses as `a = (b ? c : d)`
   - Compatible with `if`, `unless` modifiers (pri=2) so `x ? y : z if cond` works correctly

2. **Change `?` priority in `operators.rb`** from 6 to the correct value (expected: 4 or 5).
   Also evaluate whether `:` (ternalt) priority needs adjustment.

3. **Run `ruby test/test_peephole.rb`** if changed (sanity check, no docker needed).

4. **Run `make selftest`** — regression gate for MRI-compiled compiler.

5. **Run `make selftest-c`** — regression gate for self-hosted compiler.

6. **Run `./run_rubyspec spec/bug_ternary_expression_spec.rb`** to confirm all 7 tests pass
   (currently 6/7).

7. **If both gates pass**, remove the two workarounds in `treeoutput.rb`:
   - Restore line 237: `args = comma || block ? flatten(rightv) : rightv`
   - Restore line 262: `args = lv ? lv + rightv : rightv`
   - Remove the accompanying workaround code (lines 238-249 and 263-267 respectively)
   - Remove the `@bug` FIXME comments at lines 235 and 262

8. **Run `make selftest && make selftest-c` again** after the treeoutput.rb cleanup to confirm
   the restored ternary expressions compile correctly in the self-hosted compiler.

**Out of scope:**

- Fixing other `@bug` markers (Cat 1 yield, Cat 2 variable collision, Cat 4 block_given?, Cat 7
  break corruption) — those require separate investigations
- A full systematic validation of all operator precedences in `operators.rb`
- Changes to the ternary handling in `shunting.rb` unless the priority change alone is insufficient
- Adding parentheses to handle the case if the priority change proves insufficient

## Proposed Approach

**Step 1: Measure the constraint** — Before changing anything, run the failing spec to confirm
the baseline: `./run_rubyspec spec/bug_ternary_expression_spec.rb` should show 6/7 (1 failure
on the `||` test).

**Step 2: Identify the required priority** — Read `operators.rb` carefully, mapping the full
priority table. Determine what priority for `?` satisfies all four constraints listed in Scope
item 1. The expected answer is priority 4 (lower than `||`=6, `&&`=7; higher than modifiers at
2). Check: does the interaction with `:` (ternalt, pri=7) work correctly if `?` is at 4?
Specifically: when parsing `b ? c : d`, does `:` arrive with `?` on the stack and correctly
form the `[:ternalt, c, d]` node?

**Step 3: Make the change** — In `operators.rb` line 126, change `?`'s priority from 6 to the
value determined in Step 2 (expected: 4 or 5).

**Step 4: Run selftest** — `make selftest`. If it fails:
  - Revert to a known-good state (git stash, NOT git checkout without saving)
  - Diagnose the failure — is it a ternary parse error, or something else?
  - Try adjusting the priority (e.g., 5 instead of 4) and repeat
  - If no priority in the range 3-5 works, investigate whether `:` also needs adjustment

**Step 5: Run selftest-c** — `make selftest-c`. If it fails but selftest passed, the MRI-compiled
compiler is fine but the self-hosted compiler produces wrong output. This suggests the treeoutput.rb
workarounds are masking a deeper issue that only surfaces in self-hosted mode.

**Step 6: Run the ternary spec** — Confirm the failing test now passes:
  `./run_rubyspec spec/bug_ternary_expression_spec.rb` should show 7/7.

**Step 7: Remove treeoutput.rb workarounds** — Only after both selftest and selftest-c pass and
the ternary spec is green. Restore the two ternary expressions and remove the workaround code.

**Step 8: Re-run validation** — `make selftest && make selftest-c` one final time to confirm the
restored ternary expressions compile and execute correctly under the self-hosted compiler.

## Expected Payoff

- All 7 tests in `spec/bug_ternary_expression_spec.rb` pass (currently 6/7)
- Two `@bug` FIXME comments removed from `treeoutput.rb` (lines 235, 262)
- Approximately 12 lines of workaround code in `treeoutput.rb` replaced with 2 clean ternary
  expressions
- Direct advancement of [SELFHOST](../../goals/SELFHOST-clean-bootstrap.md): SELFHOST's confirmed
  bug count drops from 18 to 16 (markers 13 and 14 eliminated), and `treeoutput.rb` becomes more
  readable
- The fix validates the `operators.rb` priority table for at least one more operator pairing

## Acceptance Criteria

- [ ] `operators.rb` line 126: `?` priority changed from 6 to a value less than 6 (verified by
  reading the file)

- [ ] `./run_rubyspec spec/bug_ternary_expression_spec.rb` reports 7 runs, 0 failures (currently
  1 failure: "ternary with `||` in condition where first is truthy")

- [ ] `make selftest` passes (no regression in MRI-compiled compiler)

- [ ] `make selftest-c` passes (no regression in self-hosted compiler)

- [ ] `treeoutput.rb` line ~235: workaround `if/elsif/else` chain replaced with
  `args = comma || block ? flatten(rightv) : rightv` and the `@bug` FIXME comment removed

- [ ] `treeoutput.rb` line ~262: workaround `if/else` replaced with
  `args = lv ? lv + rightv : rightv` and the `@bug` FIXME comment removed

- [ ] Final `make selftest && make selftest-c` passes after treeoutput.rb cleanup

---
*Status: PROPOSAL - Awaiting approval*
