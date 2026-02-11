SPECAUTO
Created: 2026-02-10 23:42

# Enable Spec-Driven Autonomous Fix Planning

[AUTOMATION] Add compiler-specific instructions to the improvement planner prompt so it picks random failing specs, runs them, investigates failures, and generates validated fix plans -- closing the autonomous improvement loop.

## Goal Reference

[COMPLANG](../../goals/COMPLANG-compiler-advancement.md)

## Root Cause

The improvement planner already has full tool access: `Bash(*)`, `Task`, `Read`, `Glob`, `Grep`, `Write`, `Edit` ([bin/improve](../../../../bin/improve) line ~2346). It can run `./run_rubyspec`, `make selftest`, `./compile`, and any other command. The explore agent is more restricted (`Bash(ls:*)`, `Bash(wc:*)`, etc.) but has `Task` access and can delegate to subagents with broader capabilities.

Despite having the ability, the planner does not use it. The planner's prompt ([bin/improve](../../../../bin/improve) lines ~2258-2340) gives generic instructions: read LESSONS.md, check exploration notes, check for prior plans, then propose. There are no project-specific instructions telling the planner to run specs, compile test cases, or validate its hypotheses against live output. The planner treats every project the same way -- read docs, propose a plan -- when the compiler project has a rich test infrastructure that should be exercised before any proposal.

This is why every compiler fix plan has been rejected as "unvalidated":

1. **CASEFIX** was rejected because "run_rubyspec wasn't run" -- the planner proposed a fix without running the spec to verify its diagnosis.
2. **NOPARENS** was rejected as "wrong focus" -- the planner proposed individual fixes instead of improving the automation that generates them.

The planner has the capability to run specs but lacks the instructions to do so. The fix is to add compiler-specific guidance to the planner's prompt so that when targeting the compiler, it automatically picks a failing spec, runs it, investigates the output, and proposes a validated fix plan.

## Infrastructure Cost

Low. This adds ~20-30 lines of compiler-specific instructions to the planner prompt in [bin/improve](../../../../bin/improve), injected conditionally when `target_dir` is the compiler project. No new scripts, no new cron entries, no permission changes, no new tools. The compiler's test infrastructure already exists and works.

## Prior Plans

- [SPECPICK](../archived/SPECPICK-rubyspec-target-picker/spec.md) -- REJECTED: "aims far too small" and "just focus on rubyspec_language.txt." SPECPICK proposed a ranking script (new tooling). SPECAUTO avoids new tooling entirely -- the planner just picks a random spec and runs it directly.

- [SPECWIDE](../archived/SPECWIDE-broad-rubyspec-baseline/spec.md) -- REJECTED: "ignored the feedback to reuse the improvement planner and instead suggested building a separate infrastructure." SPECWIDE proposed a new `/fixspec` command. SPECAUTO modifies only the existing planner's prompt to make it spec-aware.

- [CASEFIX](../archived/CASEFIX-fix-case-spec-crash/spec.md) -- REJECTED: "hasn't been validated. run_rubyspec wasn't run. Wrong focus to create individual plans for unvalidated problems instead of addressing automation." SPECAUTO ensures the planner always runs specs before proposing, preventing future unvalidated proposals.

- [NOPARENS](../archived/NOPARENS-fix-noparens-default-block-segfault/spec.md) -- REJECTED: "Wrong focus to do this rather than improve automation of fixes." SPECAUTO IS the automation improvement that enables validated fix plans to be generated automatically.

## Scope

**In scope:**
- Add compiler-specific instructions to the planner prompt in [bin/improve](../../../../bin/improve) (injected when `target_dir` matches the compiler project) that direct it to: pick a random non-passing spec from the available results files, run it with `./run_rubyspec`, analyze the output (crash cause, failing assertions, missing methods), and propose a fix plan grounded in that live output
- Add similar instructions to the explore agent's prompt so that compiler explorations include spec execution, not just file reading
- The detection mechanism for "this is the compiler project" (e.g., path match on `Projects/Compiler`, or presence of `run_rubyspec` in the project root)
- A `make rubyspec-refresh` target in the compiler's [Makefile](../../../Makefile) that runs `make rubyspec-language` only if results are older than 24 hours (so the planner can trigger a refresh without redundant runs)

**Out of scope:**
- Changing tool permissions (the planner already has `Bash(*)`)
- Building new tooling, scripts, or commands (no `/fixspec`, no `pick_rubyspec_target.rb`)
- Changing the planner's core architecture or adding new agent modes
- Actually fixing any specs (that will be done by future plans that THIS enables)
- Expanding to core/ suites (future plan under COMPLANG once language/ automation is proven)

## Expected Payoff

- Every future compiler improvement plan will be validated against live spec output before being proposed -- eliminating the "unvalidated" rejection pattern
- The planner becomes the autonomous fix cycle: each daily invocation picks a random failing spec, investigates it, and produces a ready-to-execute fix plan
- No new infrastructure to maintain -- reuses existing `bin/improve`, existing skills, existing test commands
- Unblocks the entire COMPLANG goal: with ~70 non-passing language specs and daily planner invocations, the pipeline can systematically address one spec per day

## Proposed Approach

1. In [bin/improve](../../../../bin/improve), detect when `target_dir` is the compiler project (by checking for `run_rubyspec` in the project root, or by path match)
2. When targeting the compiler, inject additional instructions into the planner prompt (lines ~2258-2340) that tell it to:
   a. Read [docs/rubyspec_language.txt](../../rubyspec_language.txt) to find non-passing spec files
   b. Pick one at random (not rank -- SPECPICK was rejected for ranking)
   c. Run it: `./run_rubyspec rubyspec/language/SPECFILE.rb`
   d. Analyze the output to identify the root cause (crash, missing method, wrong result, etc.)
   e. Propose a fix plan grounded in that specific live output, including the actual error messages
   f. Ensure the proposed plan's acceptance criteria include running the spec to verify the fix AND running `make selftest` and `make selftest-c` to prevent regressions
3. Add similar spec-running instructions to the explore agent prompt so that compiler exploration notes include live diagnostic data
4. Add a `rubyspec-refresh` Makefile target for conditional results refresh (only reruns if results are older than 24 hours)

## Acceptance Criteria

- [ ] The planner's prompt, when targeting the compiler, includes instructions to pick a random non-passing spec, run it with `./run_rubyspec`, and base its proposal on the live output
- [ ] The explore agent's prompt, when targeting the compiler, includes instructions to run specs during exploration rather than only reading static files
- [ ] A test invocation of the planner against the compiler produces a plan that references specific spec output from an actual run (not just from the static results file) -- verified by checking the plan's Root Cause section cites actual error output
- [ ] The compiler-detection mechanism correctly identifies the compiler project and does not inject compiler instructions for other projects
- [ ] `make rubyspec-refresh` in the compiler project only runs `make rubyspec-language` if results are older than 24 hours
- [ ] `make selftest` and `make selftest-c` still pass (no compiler changes in this plan)
- [ ] Existing planner behavior for non-compiler projects is unaffected (verified by inspecting the prompt construction logic)

---
*Status: PROPOSAL - Awaiting approval*
