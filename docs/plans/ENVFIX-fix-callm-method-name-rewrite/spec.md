ENVFIX
Created: 2026-02-15 04:05
Created: 2026-02-15

# Fix Closure Rewrite of Method Names in :callm Nodes

[SELFHOST] Fix the environment variable rewrite (`rewrite_env_vars`) so it skips method name symbols in `:callm` AST nodes, eliminating the "variable-name collision" bug class and enabling removal of 5+ `@bug` workarounds from compiler source.

## Goal Reference

[SELFHOST](../../goals/SELFHOST-clean-bootstrap.md)

## Prior Plans

- **[BUGAUDIT](../archived/BUGAUDIT-validate-bug-workarounds/spec.md)** (Status: IMPLEMENTED): Audited all 25 `@bug` markers, confirmed 18 as still reproducing, identified 6 underlying distinct bugs, and created 7 spec files. BUGAUDIT was diagnostic — it identified and documented the bugs but explicitly scoped out *fixing* them. This plan targets the most impactful of those confirmed bugs (Category 2: variable-name collision, 7 markers) with a specific code fix.

## Root Cause

The `rewrite_env_vars` method in [transform.rb:768-801](../../transform.rb) rewrites captured variable symbols to `[:index, :__env__, N]` references for closure support. It iterates over every element of every AST node and replaces symbols found in the `env` list. However, it does **not skip position 2 of `:callm` nodes**, which holds the method name.

The `:callm` AST structure is `[:callm, object, method_name, args]`. When a captured variable has the same name as a method being called (e.g., `rest` as a local variable and `arg.rest()` as a method call), the method name at position 2 gets rewritten to a closure variable reference:

```
Before: [:callm, [:arg, 0], :rest, []]      # arg.rest()
After:  [:callm, [:arg, 0], [:index, :__env__, 3], []]  # arg.[closure_var]() -- broken
```

The code already has analogous skips for other protected positions:
- Line 773: position 0 for `:index` and `:deref` (AST node tags)
- Line 775: position 0 for `:callm` (the tag itself)
- Line 779: position 2 of `:deref` nodes (constant names)
- Line 795: position 1 of `:pattern_key` nodes

The missing skip for `:callm` position 2 is the same class of bug. The existing FIXME comment at line 769-771 acknowledges this: *"The proper solution would be to introduce more types of expression nodes in the parser."* Adding the positional skip is the incremental fix that matches the existing pattern.

This bug was confirmed by [BUGAUDIT](../archived/BUGAUDIT-validate-bug-workarounds/spec.md) as affecting 7 `@bug` markers across 6 files (Category 2), making it the single most widespread bug class in the compiler source. The [spec/bug_variable_name_collision_spec.rb](../../spec/bug_variable_name_collision_spec.rb) file documents 5 test cases, of which 2 currently fail due to this bug.

## Infrastructure Cost

Zero. The fix is a single `next if` line in [transform.rb](../../transform.rb). Workaround removal touches only existing compiler source files. Validation uses existing `make selftest`, `make selftest-c`, and `./run_rubyspec spec/bug_variable_name_collision_spec.rb`.

## Scope

**In scope:**
- Add `next if i == 2 && e[0] == :callm && ex.is_a?(Symbol)` to the rewrite loop in [transform.rb:768-801](../../transform.rb)
- Validate the fix makes the 2 failing tests in [spec/bug_variable_name_collision_spec.rb](../../spec/bug_variable_name_collision_spec.rb) pass
- Uncomment the 2 currently-commented-out crash test cases in the spec file and verify they pass
- Remove confirmed-stale `@bug` workarounds one at a time, validating each with `make selftest` and `make selftest-c`:
  - [compiler.rb:621](../../compiler.rb): rename `xrest` back to `rest`
  - [regalloc.rb:310](../../regalloc.rb): rename `xreg` back to `reg`
  - [compile_comparisons.rb:7-14](../../compile_comparisons.rb): rename `o` back to `op`, restore `"set#{op.to_s}"`
  - [lib/core/enumerator.rb:64](../../lib/core/enumerator.rb): rename `r` back to `range`
  - [output_functions.rb:57](../../output_functions.rb): remove warning comment if the pattern no longer triggers
- Update the `@bug` comment on any markers that are NOT fixed by this change (e.g., [function.rb:122](../../function.rb) — the `r = nil` bug is a different root cause: uninitialized locals, not method-name collision)

**Out of scope:**
- Full AST typing (the "proper solution" mentioned in the FIXME) — that is a much larger refactoring effort
- Fixing non-collision `@bug` categories (yield in nested blocks, ternary, block_given?, break register corruption)
- Protecting `:call` position 1 (function names) — these are typically Ruby keywords, not local variable names; no known bug markers are caused by this

## Expected Payoff

- 5 `@bug` workarounds removed from compiler source (markers 6, 7, 8, 9, 10 from [BUGAUDIT log](../archived/BUGAUDIT-validate-bug-workarounds/log.md))
- All tests in [spec/bug_variable_name_collision_spec.rb](../../spec/bug_variable_name_collision_spec.rb) pass (currently 3/5 pass, 2/5 fail, 2 commented out due to crash)
- User code with local variables shadowing method names inside closures works correctly — this is not just a compiler-internal fix but fixes a class of bugs in all compiled programs
- Direct advancement of [SELFHOST](../../goals/SELFHOST-clean-bootstrap.md): 5 fewer workarounds in compiler source, moving toward the goal of zero `@bug` markers
- The fix also advances [COMPLANG](../../goals/COMPLANG-compiler-advancement.md) indirectly: any rubyspec that uses local variables shadowing method names in blocks (a common Ruby pattern) may start passing

## Proposed Approach

1. **Add the positional skip**: In [transform.rb](../../transform.rb), add `next if i == 2 && e[0] == :callm && ex.is_a?(Symbol)` after line 779 (the `:deref` skip). This follows the exact same pattern as the existing `:deref` position-2 skip.

2. **Validate with existing spec**: Run `./run_rubyspec spec/bug_variable_name_collision_spec.rb` — the 2 currently-failing tests ("local var shadows method name inside block" and "variable named same as method in nested do blocks") should now pass.

3. **Uncomment crash cases**: Uncomment the 2 commented-out test cases in the spec file (the `VarCollisionConditionalInit#without_nil` variant and the `VarCollisionReg` crash variant). Verify they pass. Note: the `without_nil` case may be a different bug (uninitialized locals) — if it still crashes, leave it commented with an updated note.

4. **Run selftest baseline**: `make selftest && make selftest-c` to confirm the skip itself doesn't break anything.

5. **Remove workarounds one at a time**: For each of the 5 targeted markers:
   a. Make the single change (rename variable back, restore original code)
   b. Run `make selftest && make selftest-c`
   c. If it passes, commit; if it fails, investigate whether this specific case isn't covered by the `:callm` skip (e.g., it might be a string interpolation case that goes through a different AST path)

6. **Update remaining markers**: For markers not fixed (function.rb:122 `r = nil`), update the comment to note that it's a different root cause (uninitialized locals, not method-name collision).

## Acceptance Criteria

- [ ] [transform.rb](../../transform.rb) contains a `next if` skip for position 2 of `:callm` nodes in the `rewrite_env_vars` method
- [ ] `./run_rubyspec spec/bug_variable_name_collision_spec.rb` reports 0 failures for all collision-related tests (at minimum: "local var shadows method name inside block", "local var shadows method name inside lambda", "string interpolation with outer-scope variable inside block", "variable named same as method in nested do blocks")
- [ ] At least 3 of the 5 targeted `@bug` workarounds are removed (`xrest`→`rest`, `xreg`→`reg`, `o`→`op`, `r`→`range`, output_functions.rb comment), and `make selftest` + `make selftest-c` both pass after removal
- [ ] No existing test regresses: `make selftest`, `make selftest-c`, and `make spec` all pass

## Open Questions

- Does string interpolation `"set#{op.to_s}"` go through a `:callm` node for `to_s`, or does the parser generate a different AST structure for interpolation? If interpolation uses a different path, the `o`→`op` fix in [compile_comparisons.rb](../../compile_comparisons.rb) may require additional investigation. The spec test will determine this empirically.
- The `range` argument name in [lib/core/enumerator.rb:64](../../lib/core/enumerator.rb) is described as triggering "the range constructor rewrite" — this may be a different mechanism than `:callm` method-name rewriting. If so, the `r`→`range` restoration may not work, and this marker should be left in place with an updated comment.

---
*Status: PROPOSAL - Awaiting approval*
