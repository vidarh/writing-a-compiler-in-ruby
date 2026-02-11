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

- [ ] The rubyspec submodule is clean: `git diff rubyspec` shows no changes, and inside `rubyspec/`, `git status` shows no modified or untracked files
- [ ] The rubyspec submodule pointer has NOT been updated — it still points to the same upstream commit that was previously committed (`6267cc7`)
- [ ] `git status` shows a clean working tree (no modified, deleted, or untracked files except intentionally ignored ones)
- [ ] `git log --oneline -10` shows multiple thematic commits (not one giant commit) covering the different work streams
- [ ] `make selftest` passes after all commits
- [ ] [CLAUDE.md](../../CLAUDE.md) contains a "Rubyspec Submodule" section that:
  - Forbids committing any changes to the rubyspec submodule (modifications, untracked files, pointer updates)
  - States the project aspires to passing the unmodified upstream rubyspec
  - Identifies the custom runner as temporary and notes the long-term mspec migration goal
  - Requires any workarounds to live outside the submodule
- [ ] [CLAUDE.md](../../CLAUDE.md) contains a "Git Workflow" section that requires feature branches for non-trivial changes and requires committing work before starting new tasks
- [ ] The branch policy in CLAUDE.md explicitly states that the working tree should be clean before starting new work

---
*Status: APPROVED (implicit via --exec)*