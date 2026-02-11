SPECWIDE
Created: 2026-02-10 21:55
Created: 2026-02-10

# Broad Rubyspec Baseline and Autonomous Fix Cycle

[AUTOMATION] Expand tracked rubyspec coverage from 78 files (language/ only) to all core/ suites with lib/core/ implementations, add a Makefile target for the full tracked suite, and create a `/fixspec` command that picks a random failing spec from the broadened results, explores it, attempts a fix with a time limit, and either commits or defers.

## Goal Reference

[COMPLANG](../../goals/COMPLANG-compiler-advancement.md)

## Root Cause

The autonomous spec-fix pipeline is bottlenecked at two points:

1. **Tiny coverage denominator.** Only `rubyspec/language/` (78 files) is regularly tracked. The compiler implements 49 types in [lib/core/](../../lib/core/) with corresponding rubyspec suites totaling ~800+ additional spec files (e.g., core/nil: 18, core/true: 9, core/false: 9, core/symbol: 29, core/comparable: 7, core/integer: 67, core/array: 102, core/hash: 69, core/string: 114, core/range: 32, core/struct: 30, core/regexp: 24). The runner already supports arbitrary directories (`./run_rubyspec rubyspec/core/nil/`), but no Makefile target runs the full tracked set and no results file captures it.

2. **No autonomous pick-explore-fix loop.** The existing skills ([investigate-spec](../../../.claude/skills/investigate-spec/SKILL.md), [validate-fix](../../../.claude/skills/validate-fix/SKILL.md), [fixtodo](../../../.claude/commands/fixtodo.md)) require a human to choose which spec to work on. The `/fixtodo` command pulls from a manually curated TODO.md rather than from actual rubyspec results. There is no mechanism to randomly select a failing spec, timebox a fix attempt, and defer if it cannot be resolved.

These two problems compound: without broad results data, there is nothing to pick from; without an autonomous picker, the broad data sits unused.

## Infrastructure Cost

Low. The runner (`run_rubyspec`) already handles arbitrary spec directories. The Makefile already has targets for language/, integer/, and regexp/. Adding more targets is trivial. The new `/fixspec` command builds on existing skills and the results files. No new external dependencies, no Docker changes, no build system changes beyond Makefile additions.

## Scope

**In scope:**

1. Add Makefile targets that run `run_rubyspec` against all core/ suites with lib/core/ implementations (at minimum: nil, true, false, symbol, comparable, array, hash, string, range, struct, kernel, proc, class, encoding, exception, numeric, integer, regexp). Capture results to `docs/rubyspec_core.txt`.
2. Add a `make rubyspec-all` target that runs the full tracked set (language/ + all tracked core/ suites) and saves combined results.
3. Create a `/fixspec` Claude Code command (`.claude/commands/fixspec.md`) that:
   - Parses the most recent results file(s) to find all non-passing spec files
   - Picks one at random (excluding files that have a `docs/exploration/spec/` note marking them as "deferred" or "investigated")
   - Runs the investigate-spec skill on it
   - If a fix looks feasible, attempts it and validates with validate-fix
   - Has a time budget (configurable, default ~15 min wall clock); if exceeded, writes a deferral note to `docs/exploration/spec/SPECNAME.md` and moves on
   - On success: commits the fix, re-runs the target spec to confirm, updates results

**Out of scope:**
- Rewriting run_rubyspec from bash to Ruby
- Modifying rubyspec_helper.rb
- Changing the runner's timeout or classification logic
- Implementing overnight/cron scheduling (future plan under COMPLANG)
- Actually fixing any specific spec (the command does that autonomously)

## Expected Payoff

- Tracked spec files jump from 78 to ~500+ (the compiler's actual compliance surface)
- A single command (`/fixspec`) drives autonomous improvement cycles without human target selection
- Each invocation either fixes a spec (measurable progress) or produces a deferral note (knowledge capture) -- no wasted work
- The broadened baseline reveals the compiler's actual compliance posture, likely showing higher pass rates in implemented core types
- Enables future plans for regression prevention (re-running subsets) and overnight batch runs

## Proposed Approach

1. Audit which `rubyspec/core/` subdirectories have corresponding `lib/core/*.rb` implementations.
2. Add per-suite and combined Makefile targets. Use the existing `run_rubyspec` script unchanged.
3. Run the full suite once to establish baseline results in `docs/rubyspec_core.txt`.
4. Write `/fixspec` command as a Claude Code command that orchestrates the existing skills (investigate-spec, validate-fix) with random selection and time-boxing logic.
5. Test the command by running it once against the broadened results.

## Prior Plans

- [SPECPICK](../archived/SPECPICK-rubyspec-target-picker/spec.md) -- REJECTED. Rejection reason: "The focus on rubyspec_language.txt is flawed. Rubyspec_language.txt only tallies a very tiny subset of rubyspec. The plan needs an approach to running a broader, and broadening set of suites [...] Just pick a spec file at random, run an explore step on that spec if one hasn't been done, and then create a plan for attempting to fix it. [...] This plan aims far too small."

  **How this plan differs**: SPECPICK proposed a ranking script for the existing 78-file language suite. SPECWIDE addresses every criticism in the rejection: it broadens coverage to all implementable core/ suites (500+ files), replaces ranking with random selection, adds exploration and time-limited fix attempts via a new command, and includes deferral for hard problems. The ranking script is eliminated entirely -- the plan directly delivers the autonomous pick-explore-fix loop the rejection described.

## Acceptance Criteria

- [ ] `make rubyspec-all` runs the full tracked set (language/ + all tracked core/ suites) and saves results to a file that shows individual per-file PASS/FAIL/CRASH status and a combined summary
- [ ] At least 10 core/ suites beyond language/, integer/, and regexp/ are tracked (with results captured)
- [ ] `.claude/commands/fixspec.md` exists and documents an autonomous pick-explore-fix cycle that reads from the broadened results, picks randomly, invokes investigation, attempts fixes with a time limit, and defers if necessary
- [ ] Running the fixspec command against the broadened results either produces a commit fixing a spec or a deferral note explaining why the spec was deferred -- no silent failures or missing output

## Open Questions

- Should the full suite run be a single `run_rubyspec` invocation against multiple directories, or separate per-suite invocations concatenated? (The runner supports single directories; a wrapper script may be needed for multiple.)
- What is the right default time budget for a fix attempt? 15 minutes? 30 minutes? (The runner already has a 30s timeout per spec execution; this is about the AI's investigation+fix time.)

---
*Status: REJECTED — This ignored the feedback to reuse the improvement planner and instead suggested building a separate infrastructure.*