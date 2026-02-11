PLANGUIDE
Created: 2026-02-11 00:08

# Add Improvement Planner Guidance to Compiler Project

> **User direction (2026-02-11 00:16):** Rather than add this in README, which is targeted more toward humans, add an '@' reference to a separate file in docs/. Be cautious about referencing the existing skills, which are not particularly well tested - investigate them before making a decision.

[AUTOMATION] Create a dedicated guidance file in `docs/` and add an `@` reference to it from README.md, so the planner knows to pick random failing specs, run them live, and propose validated fixes.

## Goal Reference

[COMPLANG](../../goals/COMPLANG-compiler-advancement.md)

## Root Cause

The improvement planner reads README.md and CLAUDE.md when it runs in a project directory. The Desktop project exploits this with a "Do NOT propose" / "DO propose" section that steers the planner toward high-value work. The compiler project has no equivalent. Its CLAUDE.md covers coding rules and its README.md is targeted toward humans. Neither mentions the test infrastructure (`./run_rubyspec`, `make selftest`, `make selftest-c`) or the existing results files. The planner has full tool access and can run any command, but without guidance it defaults to reading docs and proposing plans based on assumptions rather than live output. This is why five of six prior plans were rejected.

## Skill Investigation

The project has three existing skills (`investigate-spec`, `validate-fix`, `create-minimal-test`) defined in `.claude/skills/`. All three are well-documented but have **no evidence of actual testing or usage** — no execution logs, no git commits showing invocations, and prior exploration notes explicitly flag permission issues preventing autonomous execution. These skills should **not** be referenced in the guidance until they have been validated through real use. The guidance file should describe the workflow directly (run specs, analyze failures, propose fixes) rather than delegating to untested skills.

## Infrastructure Cost

Minimal. This creates one new file in `docs/` and adds a single `@` reference line to README.md. No code, no Makefile targets, no new tools, no results files.

## Prior Plans

- [SPECAUTO](../archived/SPECAUTO-enable-spec-driven-autonomous-fix-planning/spec.md) -- REJECTED after 3 revisions: "confused solutions that are pointlessly complicated and/or not generic enough." SPECAUTO bundled this guidance with Makefile targets for 5+ new suites, results file management, `rubyspec-refresh` with staleness checks, and COMPLANG goal updates. PLANGUIDE extracts only the planner guidance -- the one piece that directly addresses the planner's behavior -- and defers infrastructure to future plans.

## Scope

**In scope:**
- Create a new file `docs/improvement-planner.md` containing project-specific guidance for the improvement planner
- Add an `@docs/improvement-planner.md` reference to [README.md](../../../README.md) so the planner discovers it

**Out of scope:**
- Makefile targets (the runner already supports arbitrary directories; new targets are a separate plan)
- Generating or managing results files
- Modifying CLAUDE.md, `bin/improve`, or any shared tooling
- Updating the COMPLANG goal
- Fixing any specs
- Referencing the existing skills (untested; see Skill Investigation above)

## Expected Payoff

- Future planner invocations will run specs live before proposing, eliminating the "unvalidated" rejection pattern
- The planner will target spec fixes (which the user wants) instead of meta-automation (which has been repeatedly rejected)
- Follows a proven pattern already working in the Desktop project
- Keeps README.md human-focused while providing machine-readable guidance via `@` reference

## Proposed Approach

1. Create `docs/improvement-planner.md` containing: a brief note about the test infrastructure, instructions to pick a random spec and run it with `./run_rubyspec`, instructions to investigate failures and propose fix plans grounded in live output, and short "Do NOT propose" / "DO propose" lists tailored to compiler work.
2. Add a single `@docs/improvement-planner.md` reference line to README.md so the planner picks it up automatically.

## Acceptance Criteria

- [ ] `docs/improvement-planner.md` exists with guidance for picking, running, and investigating specs before proposing fix plans
- [ ] The file includes "Do NOT propose" guidance that excludes unvalidated fix proposals and automation-for-automation's-sake plans
- [ ] The file includes "DO propose" guidance that favors compiler/library fixes grounded in live spec output
- [ ] The file does NOT reference the existing skills (`investigate-spec`, `validate-fix`, `create-minimal-test`)
- [ ] [README.md](../../../README.md) contains an `@docs/improvement-planner.md` reference
- [ ] No other files are modified

---
*Status: APPROVED (implicit via --exec)*
