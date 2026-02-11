PLANGUIDE
Created: 2026-02-11 00:08

# Add Improvement Planner Guidance to Compiler Project

[AUTOMATION] Add a short "Improvement Planner" section to the compiler's README.md, following the same pattern the Desktop project uses, so the planner knows to pick random failing specs, run them live, and propose validated fixes.

## Goal Reference

[COMPLANG](../../goals/COMPLANG-compiler-advancement.md)

## Root Cause

The improvement planner reads README.md and CLAUDE.md when it runs in a project directory. The Desktop project exploits this with a "Do NOT propose" / "DO propose" section that steers the planner toward high-value work. The compiler project has no equivalent. Its CLAUDE.md covers coding rules and its README.md covers project overview. Neither mentions the test infrastructure (`./run_rubyspec`, `make selftest`, `make selftest-c`), the existing results files, or the existing skills (`investigate-spec`, `validate-fix`). The planner has full tool access and can run any command, but without guidance it defaults to reading docs and proposing plans based on assumptions rather than live output. This is why five of six prior plans were rejected.

## Infrastructure Cost

Zero. This adds a text section to an existing file. No code, no Makefile targets, no new tools, no results files.

## Prior Plans

- [SPECAUTO](../archived/SPECAUTO-enable-spec-driven-autonomous-fix-planning/spec.md) -- REJECTED after 3 revisions: "confused solutions that are pointlessly complicated and/or not generic enough." SPECAUTO bundled this guidance with Makefile targets for 5+ new suites, results file management, `rubyspec-refresh` with staleness checks, and COMPLANG goal updates. PLANGUIDE extracts only the README guidance -- the one piece that directly addresses the planner's behavior -- and defers infrastructure to future plans.

## Scope

**In scope:**
- Add an "Improvement Planner" section to [README.md](../../../README.md) with project-specific guidance for the planner, modeled on the Desktop project's equivalent section

**Out of scope:**
- Makefile targets (the runner already supports arbitrary directories; new targets are a separate plan)
- Generating or managing results files
- Modifying CLAUDE.md, `bin/improve`, or any shared tooling
- Updating the COMPLANG goal
- Fixing any specs

## Expected Payoff

- Future planner invocations will run specs live before proposing, eliminating the "unvalidated" rejection pattern
- The planner will target spec fixes (which the user wants) instead of meta-automation (which has been repeatedly rejected)
- Follows a proven pattern already working in the Desktop project

## Proposed Approach

Add a section to README.md containing: a brief note about the test infrastructure, instructions to pick a random spec and run it with `./run_rubyspec`, instructions to investigate failures and propose fix plans grounded in live output, and short "Do NOT propose" / "DO propose" lists tailored to compiler work.

## Acceptance Criteria

- [ ] [README.md](../../../README.md) contains an "Improvement Planner" section with guidance for picking, running, and investigating specs before proposing fix plans
- [ ] The section includes "Do NOT propose" guidance that excludes unvalidated fix proposals and automation-for-automation's-sake plans
- [ ] The section includes "DO propose" guidance that favors compiler/library fixes grounded in live spec output
- [ ] No files other than README.md are modified

---
*Status: APPROVED (implicit via --exec)*