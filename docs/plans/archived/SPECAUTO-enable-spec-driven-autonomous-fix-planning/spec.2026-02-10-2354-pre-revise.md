SPECAUTO
Created: 2026-02-10 23:42

# Enable Spec-Driven Autonomous Fix Planning

[AUTOMATION] Add an "Improvement Planner" section to the compiler project's own documentation that instructs the planner to pick random failing specs, run them, investigate failures, and generate validated fix plans -- closing the autonomous improvement loop.

## Goal Reference

[COMPLANG](../../goals/COMPLANG-compiler-advancement.md)

## Root Cause

The improvement planner runs inside the compiler's directory and reads CLAUDE.md and README.md automatically (this is standard Claude Code behavior). The Desktop project already exploits this: its README.md contains an "Improvement Planner" section with project-specific guidance ("Do NOT propose", "DO propose", exploration note paths, etc.). The planner follows those instructions because it reads them as part of the project context.

The compiler project has no equivalent section. Its CLAUDE.md covers coding rules (never edit rubyspec, never add operator special cases, etc.) and its README.md covers the project overview. Neither document tells the planner anything about the compiler's rich test infrastructure -- `./run_rubyspec`, `docs/rubyspec_language.txt`, `make selftest`, `make selftest-c` -- or how to use it when proposing improvements.

This is why every compiler fix plan has been rejected as "unvalidated":

1. **CASEFIX** was rejected because "run_rubyspec wasn't run" -- the planner proposed a fix without running the spec to verify its diagnosis.
2. **NOPARENS** was rejected as "wrong focus" -- the planner proposed individual fixes instead of improving the automation that generates them.

The planner has full tool access (`Bash(*)`, `Task`, `Read`, etc.) and can run any compiler command. It just doesn't know it should. The fix is to add compiler-specific planner guidance to the compiler project's own documentation, following the same pattern the Desktop project already uses.

## Infrastructure Cost

Minimal. This adds an "Improvement Planner" section to the compiler's README.md (the same mechanism Desktop already uses) and a convenience Makefile target. No changes to `bin/improve` or any shared tooling. No new scripts, no new cron entries, no permission changes.

## Prior Plans

- [SPECPICK](../archived/SPECPICK-rubyspec-target-picker/spec.md) -- REJECTED: "aims far too small" and "just focus on rubyspec_language.txt." SPECPICK proposed a ranking script (new tooling). SPECAUTO avoids new tooling entirely.

- [SPECWIDE](../archived/SPECWIDE-broad-rubyspec-baseline/spec.md) -- REJECTED: "ignored the feedback to reuse the improvement planner and instead suggested building a separate infrastructure." SPECWIDE proposed a new `/fixspec` command. SPECAUTO works entirely through the existing planner by adding project-local documentation.

- [CASEFIX](../archived/CASEFIX-fix-case-spec-crash/spec.md) -- REJECTED: "hasn't been validated. run_rubyspec wasn't run. Wrong focus to create individual plans for unvalidated problems instead of addressing automation." SPECAUTO ensures the planner always runs specs before proposing, preventing future unvalidated proposals.

- [NOPARENS](../archived/NOPARENS-fix-noparens-default-block-segfault/spec.md) -- REJECTED: "Wrong focus to do this rather than improve automation of fixes." SPECAUTO IS the automation improvement that enables validated fix plans to be generated automatically.

## Scope

**In scope:**
- Add an "Improvement Planner" section to the compiler's [README.md](../../../README.md) that instructs the planner to: pick a random non-passing spec from the available results files, run it with `./run_rubyspec`, analyze the output (crash cause, failing assertions, missing methods), and propose a fix plan grounded in that live output
- Include guidance for the explore agent in the same section so that compiler explorations include spec execution, not just file reading
- A `make rubyspec-refresh` target in the compiler's [Makefile](../../../Makefile) that runs `make rubyspec-language` only if results are older than 24 hours (so the planner can trigger a refresh without redundant runs)

**Out of scope:**
- Editing `bin/improve` or any shared tooling (project-specific instructions belong in the project's own documentation)
- Building new tooling, scripts, or commands (no `/fixspec`, no `pick_rubyspec_target.rb`)
- Changing tool permissions (the planner already has `Bash(*)`)
- Changing the planner's core architecture or adding new agent modes
- Actually fixing any specs (that will be done by future plans that THIS enables)
- Expanding to core/ suites (future plan under COMPLANG once language/ automation is proven)

## Expected Payoff

- Every future compiler improvement plan will be validated against live spec output before being proposed -- eliminating the "unvalidated" rejection pattern
- The planner becomes the autonomous fix cycle: each daily invocation picks a random failing spec, investigates it, and produces a ready-to-execute fix plan
- No new infrastructure to maintain -- reuses existing planner, existing test commands, and the same documentation-driven mechanism Desktop already uses
- Unblocks the entire COMPLANG goal: with ~70 non-passing language specs and daily planner invocations, the pipeline can systematically address one spec per day

## Proposed Approach

1. Add an "Improvement Planner" section to [README.md](../../../README.md) containing:
   a. Instructions to read [docs/rubyspec_language.txt](../../rubyspec_language.txt) to find non-passing spec files
   b. Instructions to pick one at random (not rank -- SPECPICK was rejected for ranking)
   c. Instructions to run it: `./run_rubyspec rubyspec/language/SPECFILE.rb`
   d. Instructions to analyze the output to identify the root cause (crash, missing method, wrong result, etc.)
   e. Instructions to propose a fix plan grounded in that specific live output, including actual error messages
   f. A requirement that proposed plans' acceptance criteria include running the spec to verify the fix AND running `make selftest` and `make selftest-c` to prevent regressions
   g. Guidance for exploration runs to include live spec execution, not just static file reading
   h. "Do NOT propose" and "DO propose" lists tailored to compiler improvement patterns (e.g., do not propose unvalidated fixes; do propose fixes backed by live spec output)
2. Add a `rubyspec-refresh` Makefile target for conditional results refresh (only reruns if results are older than 24 hours)

## Acceptance Criteria

- [ ] The compiler's README.md contains an "Improvement Planner" section with instructions to pick a random non-passing spec, run it with `./run_rubyspec`, and base proposals on the live output
- [ ] The section includes guidance for exploration runs to execute specs rather than only reading static files
- [ ] The section includes "Do NOT propose" guidance that excludes unvalidated fix proposals and individual spec fixes without prior live investigation
- [ ] The section includes "DO propose" guidance that favors fixes backed by live spec output and automation improvements
- [ ] `make rubyspec-refresh` in the compiler project only runs `make rubyspec-language` if results are older than 24 hours
- [ ] `bin/improve` is NOT modified (all instructions come from compiler project documentation)
- [ ] `make selftest` and `make selftest-c` still pass (no compiler changes in this plan)
- [ ] A test invocation of the planner against the compiler, after the README.md changes, produces a plan that references specific spec output from an actual run -- verified by checking the plan's Root Cause section cites actual error output

---
*Status: PROPOSAL - Awaiting approval*
