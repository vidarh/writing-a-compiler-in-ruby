GITCLEAN
Created: 2026-02-11

# Commit Dirty Working Tree, Clean Rubyspec Submodule, and Establish Branch Policy

[CLEANUP] Clean up the rubyspec submodule (revert all local modifications and remove junk files), commit all other uncommitted changes as organized thematic commits, and add branching/submodule hygiene rules to [CLAUDE.md](../../CLAUDE.md).

## Root Cause

The repository has accumulated a large volume of uncommitted changes from multiple work streams: the executed [DOCCLN](../archived/DOCCLN-doc-cleanup/spec.md) doc cleanup plan, peephole optimizer development, the planning infrastructure (docs/plans/, docs/goals/, docs/exploration/), new tools, and new spec files. These changes span 16 modified/deleted tracked files and 90+ untracked files, all sitting in the working tree on master with nothing staged.

Additionally, the rubyspec submodule has been polluted with local modifications to 3 tracked files (`core/integer/fixtures/classes.rb`, `core/integer/shared/abs.rb`, `spec_helper.rb`) and 20+ untracked junk files (temp tests, scratch scripts). This violates the project's core principle: rubyspec must remain unmodified. The project aspires to passing the unmodified upstream rubyspec suite. The current custom runner (`run_rubyspec`) is a temporary measure; as it approaches feature parity with real mspec, migration to upstream mspec is the long-term goal. Any modifications to rubyspec — even "helpful" ones — undermine this aspiration.

This happened because there is no branching or commit hygiene policy, and no explicit rule forbidding submodule changes. Work is done directly on master, there is no rule requiring changes to be committed before moving to the next task, and CLAUDE.md's "never edit rubyspec" rule doesn't explicitly cover the submodule pointer or untracked file dumping. The result is an increasingly risky working tree where unrelated changes are interleaved and a single bad `git checkout .` or `git clean -fd` could destroy hours of work.

## Infrastructure Cost

Zero. This plan uses only git commands and edits [CLAUDE.md](../../CLAUDE.md). No new tooling, no CI integration, no external dependencies.

## Scope

**In scope:**

1. **Clean the rubyspec submodule** (first priority — do this before any commits):
   - Revert all 3 modified tracked files inside `rubyspec/` to their upstream state (`git checkout .` inside the submodule)
   - Remove all 20+ untracked files and directories inside `rubyspec/` (`git clean -fd` inside the submodule)
   - Reset the submodule pointer back to the committed upstream ref (`6267cc7`), discarding the dirty `d499524-dirty` state
   - Verify `git diff rubyspec` shows no changes after cleanup

2. **Commit all other uncommitted changes** as a series of thematic commits on master, grouped by work stream:
   - DOCCLN results: doc deletions, KNOWN_ISSUES/TODO/bignums/control_flow edits
   - Peephole optimizer work: peephole.rb, peephole_optimizer_plan.md, test_peephole_fixture.rb
   - Planning infrastructure: docs/plans/, docs/goals/, docs/exploration/, improvement-planner docs
   - Project config: CLAUDE.md, README.md updates
   - New tools and specs: tools/, spec/minimal_heredoc_spec.rb, docs/rubyspec_regexp.txt, docs/spec.txt

3. **Add a "Git Workflow" section to [CLAUDE.md](../../CLAUDE.md)** establishing:
   - All non-trivial changes must happen on a feature branch, not directly on master
   - Feature branches must be committed and merged (not left as dirty working tree state)
   - Commits should be thematic (one logical change per commit, not a dump of everything)
   - The working tree should be clean (no uncommitted changes) before starting new work

4. **Add a "Rubyspec Submodule" section to [CLAUDE.md](../../CLAUDE.md)** establishing:
   - The rubyspec submodule must NEVER have local modifications committed — no changes to tracked files, no untracked files, no submodule pointer updates (unless deliberately tracking a new upstream release)
   - The project aspires to passing the *unmodified* upstream rubyspec suite
   - The custom runner (`run_rubyspec`) is a temporary measure; long-term, migration to upstream mspec is the goal
   - Any workarounds needed to run specs must live in the custom runner or in compiler stubs *outside* the submodule, never inside it
   - If `git status` shows the rubyspec submodule as dirty, it must be cleaned before committing

**Out of scope:**
- Setting up CI, pre-commit hooks, or automated branch protection
- Rebasing or rewriting existing git history
- Changing the project's build or test workflow
- Migrating to upstream mspec (that is a separate, future effort)
- Relocating any workaround stubs that currently live inside rubyspec (if any such stubs are needed, that should be a separate plan)

## Expected Payoff

- The rubyspec submodule is restored to a pristine upstream state
- The working tree goes from 100+ dirty files to clean, with all work safely committed
- Future AI agent sessions start from a clean baseline instead of inheriting a confusing dirty state
- Explicit CLAUDE.md rules prevent the rubyspec submodule from being polluted again
- The branching policy prevents the same accumulation of uncommitted work from recurring
- Thematic commits make `git log` useful for understanding what changed and why
- Reduces risk of accidental data loss from stale uncommitted changes

## Proposed Approach

**Phase 1: Clean rubyspec submodule**

1. Inside the `rubyspec/` submodule directory, revert all tracked file modifications: `git checkout .`
2. Inside the `rubyspec/` submodule directory, remove all untracked files: `git clean -fd`
3. In the parent repo, reset the submodule to the committed ref: `git submodule update --init rubyspec`
4. Verify: `git diff rubyspec` should show no output; `git status` should no longer show the rubyspec submodule as modified

**Phase 2: Commit dirty working tree**

5. Examine the remaining dirty state and group changes by work stream
6. Stage and commit each group as a separate, well-described commit on master (since these changes are already on master and there is no clean baseline to branch from)
7. After each commit, run `make selftest` to verify the compiler still works (catches any accidental inclusion of files that break the build)

**Phase 3: Add CLAUDE.md policies**

8. Add a "Rubyspec Submodule" section to [CLAUDE.md](../../CLAUDE.md) with the rules from scope item 4
9. Add a "Git Workflow" section to [CLAUDE.md](../../CLAUDE.md) with branching and commit hygiene rules from scope item 3
10. Commit the CLAUDE.md changes as a final commit
11. Verify the working tree is clean after all commits

## Acceptance Criteria

- [x] The rubyspec submodule is clean: `git diff rubyspec` shows no changes, and inside `rubyspec/`, `git status` shows no modified or untracked files
- [x] The rubyspec submodule pointer has NOT been updated — it still points to the same upstream commit that was previously committed (`6267cc7`)
- [ ] `git status` shows a clean working tree (no modified, deleted, or untracked files except intentionally ignored ones)
  FAIL: Working tree has 7 dirty items: 2 modified files (docs/goals/PARSARCH-parser-architecture.md, docs/goals/SELFHOST-clean-bootstrap.md) and 5 untracked files (GITCLEAN plan execution artifacts: exec log, exec prompt, post-exec spec, test log, test-adequacy.md). These are post-execution artifacts created by the plan framework after the plan completed, but the criterion is absolute.
- [x] `git log --oneline -10` shows multiple thematic commits (not one giant commit) covering the different work streams
- [x] `make selftest` passes after all commits
- [x] [CLAUDE.md](../../CLAUDE.md) contains a "Rubyspec Submodule" section that:
  - Forbids committing any changes to the rubyspec submodule (modifications, untracked files, pointer updates)
  - States the project aspires to passing the unmodified upstream rubyspec
  - Identifies the custom runner as temporary and notes the long-term mspec migration goal
  - Requires any workarounds to live outside the submodule
- [x] [CLAUDE.md](../../CLAUDE.md) contains a "Git Workflow" section that requires feature branches for non-trivial changes and requires committing work before starting new tasks
- [x] The branch policy in CLAUDE.md explicitly states that the working tree should be clean before starting new work

## Implementation Details

### Phase 1: Rubyspec submodule cleanup

The rubyspec submodule (committed ref `6267cc7`, currently `d499524-dirty`) has:

**3 modified tracked files** (inside `rubyspec/`):
- `core/integer/fixtures/classes.rb`
- `core/integer/shared/abs.rb`
- `spec_helper.rb`

**20+ untracked files** (inside `rubyspec/`):
- `compiler_stubs.rb`
- `language/check_all_language_specs.sh`
- `rubyspec_temp_bit_or_spec.rb`, `simple_integer_basic_spec.rb`, `simple_integer_spec.rb`, `simple_plus_bignum_test.rb`, `simple_true_to_s_spec.rb`
- `temp_bignum_plus_test.rb`, `temp_simple_add.rb`
- `test_bignum_add2.rb`, `test_bignum_add_overflow.rb`, `test_bignum_basic.rb`, `test_bignum_simple.rb`, `test_failing_spec.rb`, `test_just_puts.rb`, `test_multilimb_bignum.rb`, `test_simple_bignum_add.rb`
- `simple_tests/` (directory)

**Cleanup commands** (run from parent repo root):
1. `cd rubyspec && git checkout .` — reverts 3 modified tracked files
2. `cd rubyspec && git clean -fd` — removes all untracked files/dirs
3. `git submodule update --init rubyspec` — resets submodule pointer back to `6267cc7`
4. Verify: `git diff rubyspec` should produce no output

**Note on `compiler_stubs.rb`**: This file inside the submodule should be reviewed before deletion. If it contains stubs needed by `run_rubyspec`, those stubs need to be relocated outside the submodule (e.g., into the parent project's `lib/` or `spec/` support files). However, per the plan scope, relocating stubs is out-of-scope; just clean it and note if anything breaks.

### Phase 2: Thematic commits

The dirty working tree has **16 modified/deleted tracked files** and **8 untracked file groups**. These group into 5 thematic commits:

**Commit 1: Doc cleanup (DOCCLN results)**
Files to stage:
- `docs/DEVELOPMENT_RULES.md` (deleted)
- `docs/KERNEL_MIGRATION_PLAN.md` (deleted)
- `docs/REJECTED_APPROACH_METHOD_CHAINING.md` (deleted)
- `docs/RUBYSPEC_CRASH_ANALYSIS.md` (deleted)
- `docs/RUBYSPEC_INTEGRATION.md` (deleted)
- `docs/KNOWN_ISSUES.md` (modified — condensed, renumbered, updated stats)
- `docs/TODO.md` (modified — condensed, updated stats)
- `docs/bignums.md` (modified — heavily condensed from 1678 to ~183 lines)
- `docs/control_flow_as_expressions.md` (modified — updated references to removed docs)

**Commit 2: Peephole optimizer improvements**
Files to stage:
- `peephole.rb` (modified — generalized mov self-to-self removal, removed unsafe push/pop and cmpl patterns, added `return` to stack folding)
- `docs/peephole_optimizer_plan.md` (modified — rewritten with clearer goals and refactor plan)
- `test/test_peephole_fixture.rb` (modified — added `test_mov_reg_to_same_reg_is_removed` and `test_movb_same_reg_is_removed`)

**Commit 3: Planning infrastructure**
Files to stage:
- `docs/plans/` (new directory tree — all plan specs, reviews, logs, archived plans)
- `docs/goals/` (new directory — 4 goal files: CODEGEN, COMPLANG, PURERB, SELFHOST)
- `docs/exploration/` (new directory — 3 exploration docs)
- `docs/improvement-planner.md` (new — planner guidance doc)
- `docs/improvement-planner-review.md` (new — planner review/stats)

**Commit 4: Project config updates**
Files to stage:
- `CLAUDE.md` (modified — added "Slow targets" note in Testing section)
- `README.md` (modified — added improvement-planner reference, vision section)

**Commit 5: New tools, specs, and test results**
Files to stage:
- `tools/asm_diff_counts.rb` (new — asm diff counting tool)
- `tools/check_planguide.sh` (new — plan guide checker script)
- `spec/minimal_heredoc_spec.rb` (new — heredoc interpolation spec)
- `docs/rubyspec_regexp.txt` (new — regexp spec run results)
- `docs/spec.txt` (modified — updated spec results)

**Note**: The `tools/` directory already has tracked files (`asm_ngram.rb`, `check_selftest.sh`, `compare_asm.rb`, `vm.rb~`). Only the 2 new untracked files need staging.

**Commit ordering rationale**: DOCCLN first (pure doc changes, lowest risk), then peephole (code change that needs selftest validation), then infrastructure/config (no code impact), then tools/specs (no code impact). Selftest should be run after commit 2 since it's the only commit touching compiler code.

### Phase 3: CLAUDE.md policy additions

**File**: [CLAUDE.md](../../CLAUDE.md) (currently 318 lines)

**Insertion point**: After the last CRITICAL RULE section ("NEVER Delete Failing Specs", ending at line 157) and before "## Project Overview" (line 158). This keeps all rules/policies together, separate from reference documentation.

**New section 1 — "Rubyspec Submodule"**: A CRITICAL RULE section covering:
- Never modify tracked files inside `rubyspec/`
- Never leave untracked files inside `rubyspec/`
- Never commit a dirty submodule pointer (unless deliberately tracking a new upstream release)
- Project aspiration: pass unmodified upstream rubyspec
- `run_rubyspec` is temporary; long-term goal is upstream mspec
- Workarounds must live outside the submodule (in `run_rubyspec`, `spec/` support files, or `lib/core/`)
- If `git status` shows rubyspec as dirty, clean it before committing

**New section 2 — "Git Workflow"**: A rule section covering:
- Non-trivial changes should happen on feature branches, not directly on master
- Work must be committed before starting new tasks
- Commits should be thematic (one logical change per commit)
- Working tree should be clean before starting new work
- Exception: quick single-line fixes can go directly on master

**Style/format**: Follow the existing CLAUDE.md pattern — `## CRITICAL RULE:` header, bold rule statement, bullet lists with checkmark/cross emojis, "Why this rule exists" subsection. Match the tone and formatting of existing rules like "NEVER EDIT RUBYSPEC FILES".

## Execution Steps

1. [ ] **Review rubyspec `compiler_stubs.rb` before cleanup** — Read `rubyspec/compiler_stubs.rb` to check if it contains stubs used by `run_rubyspec` or the test infrastructure. If yes, note what needs relocating (out of scope for this plan but should be flagged). If no, proceed with cleanup.

2. [ ] **Clean rubyspec submodule: revert tracked files** — Run `cd rubyspec && git checkout .` to revert modifications to `core/integer/fixtures/classes.rb`, `core/integer/shared/abs.rb`, and `spec_helper.rb`.

3. [ ] **Clean rubyspec submodule: remove untracked files** — Run `cd rubyspec && git clean -fd` to remove all 20+ junk files and the `simple_tests/` directory.

4. [ ] **Reset rubyspec submodule pointer** — Run `git submodule update --init rubyspec` from the parent repo root. Verify with `git diff rubyspec` (should show no output) and check `git status` no longer shows `M rubyspec`.

5. [ ] **Commit 1: Doc cleanup** — Stage the 5 deleted docs and 4 modified docs: `git add docs/DEVELOPMENT_RULES.md docs/KERNEL_MIGRATION_PLAN.md docs/REJECTED_APPROACH_METHOD_CHAINING.md docs/RUBYSPEC_CRASH_ANALYSIS.md docs/RUBYSPEC_INTEGRATION.md docs/KNOWN_ISSUES.md docs/TODO.md docs/bignums.md docs/control_flow_as_expressions.md`. Commit with message: "Clean up documentation: remove obsolete docs, condense active ones".

6. [ ] **Commit 2: Peephole optimizer** — Stage: `git add peephole.rb docs/peephole_optimizer_plan.md test/test_peephole_fixture.rb`. Commit with message: "Improve peephole optimizer: generalize mov removal, update plan and tests".

7. [ ] **Validate after peephole commit** — Run `make selftest` to confirm the peephole.rb changes don't break the compiler. This is the only commit touching compiler code, so only one validation checkpoint is needed.

8. [ ] **Commit 3: Planning infrastructure** — Stage: `git add docs/plans/ docs/goals/ docs/exploration/ docs/improvement-planner.md docs/improvement-planner-review.md`. Commit with message: "Add improvement planning infrastructure: plans, goals, exploration docs".

9. [ ] **Commit 4: Project config** — Stage: `git add CLAUDE.md README.md`. Commit with message: "Update project config: add slow-target guidance to CLAUDE.md, add vision to README".

10. [ ] **Commit 5: New tools, specs, and test results** — Stage: `git add tools/asm_diff_counts.rb tools/check_planguide.sh spec/minimal_heredoc_spec.rb docs/rubyspec_regexp.txt docs/spec.txt`. Commit with message: "Add new tools, heredoc spec, and updated test results".

11. [ ] **Verify clean state after commits** — Run `git status` and confirm working tree is clean (no modified, deleted, or untracked files). If anything remains, investigate and stage/commit as appropriate.

12. [ ] **Add "Rubyspec Submodule" section to CLAUDE.md** — Insert a new `## CRITICAL RULE: Rubyspec Submodule Hygiene` section after the "NEVER Delete Failing Specs" section (after line 157) and before "## Project Overview" (line 158). Content per the Implementation Details above.

13. [ ] **Add "Git Workflow" section to CLAUDE.md** — Insert a new `## Git Workflow` section immediately after the Rubyspec Submodule section. Content per the Implementation Details above.

14. [ ] **Commit 6: CLAUDE.md policies** — Stage: `git add CLAUDE.md`. Commit with message: "Add rubyspec submodule hygiene and git workflow policies to CLAUDE.md".

15. [ ] **Final verification** — Run `git status` to confirm clean working tree. Run `git log --oneline -10` to verify 6 thematic commits are present. Run `make selftest` one final time to confirm everything still works. Verify `git diff rubyspec` shows no output.

---
*Status: IMPLEMENTED (manual) — The remaining modified files are due to spearate changes ongoing, so this is *approved*.*