GITCLEAN
Created: 2026-02-11

# Commit Dirty Working Tree and Establish Branch Policy

[CLEANUP] Commit all uncommitted changes in the repository as organized, thematic commits, then add a branching policy to [CLAUDE.md](../../CLAUDE.md) requiring feature branches for future work.

## Root Cause

The repository has accumulated a large volume of uncommitted changes from multiple work streams: the executed [DOCCLN](../archived/DOCCLN-doc-cleanup/spec.md) doc cleanup plan, peephole optimizer development, the planning infrastructure (docs/plans/, docs/goals/, docs/exploration/), new tools, and new spec files. These changes span 16 modified/deleted tracked files and 90+ untracked files, all sitting in the working tree on master with nothing staged.

This happened because there is no branching or commit hygiene policy. Work is done directly on master, and there is no rule requiring changes to be committed before moving to the next task. The result is an increasingly risky working tree where unrelated changes are interleaved and a single bad `git checkout .` or `git clean -fd` could destroy hours of work.

## Infrastructure Cost

Zero. This plan uses only git commands and edits [CLAUDE.md](../../CLAUDE.md). No new tooling, no CI integration, no external dependencies.

## Scope

**In scope:**

1. Commit all current uncommitted changes as a series of thematic commits on master, grouped by work stream:
   - DOCCLN results: doc deletions, KNOWN_ISSUES/TODO/bignums/control_flow edits
   - Peephole optimizer work: peephole.rb, peephole_optimizer_plan.md, test_peephole_fixture.rb
   - Planning infrastructure: docs/plans/, docs/goals/, docs/exploration/, improvement-planner docs
   - Project config: CLAUDE.md, README.md updates
   - New tools and specs: tools/, spec/minimal_heredoc_spec.rb, docs/rubyspec_regexp.txt, docs/spec.txt
   - Rubyspec submodule update (if appropriate)

2. Add a "Git Workflow" section to [CLAUDE.md](../../CLAUDE.md) establishing:
   - All non-trivial changes must happen on a feature branch, not directly on master
   - Feature branches must be committed and merged (not left as dirty working tree state)
   - Commits should be thematic (one logical change per commit, not a dump of everything)
   - The working tree should be clean (no uncommitted changes) before starting new work

**Out of scope:**
- Setting up CI, pre-commit hooks, or automated branch protection
- Rebasing or rewriting existing git history
- Changing the project's build or test workflow

## Expected Payoff

- The working tree goes from 100+ dirty files to clean, with all work safely committed
- Future AI agent sessions start from a clean baseline instead of inheriting a confusing dirty state
- The branching policy prevents the same accumulation from recurring
- Thematic commits make `git log` useful for understanding what changed and why
- Reduces risk of accidental data loss from stale uncommitted changes

## Proposed Approach

1. Examine the dirty state and group changes by work stream
2. Stage and commit each group as a separate, well-described commit on master (since these changes are already on master and there is no clean baseline to branch from)
3. Add a "Git Workflow" section to [CLAUDE.md](../../CLAUDE.md) with branching and commit hygiene rules
4. Verify the working tree is clean after all commits

## Acceptance Criteria

- [ ] `git status` shows a clean working tree (no modified, deleted, or untracked files except intentionally ignored ones)
- [ ] `git log --oneline -10` shows multiple thematic commits (not one giant commit) covering the different work streams
- [ ] [CLAUDE.md](../../CLAUDE.md) contains a "Git Workflow" section that requires feature branches for non-trivial changes and requires committing work before starting new tasks
- [ ] The branch policy in CLAUDE.md explicitly states that the working tree should be clean before starting new work

## Open Questions

- Should the rubyspec submodule change be committed as-is, or does it need separate verification? The submodule shows "new commits, modified content, untracked content" which may include local modifications that should not be committed.

---
*Status: PROPOSAL - Awaiting approval*
