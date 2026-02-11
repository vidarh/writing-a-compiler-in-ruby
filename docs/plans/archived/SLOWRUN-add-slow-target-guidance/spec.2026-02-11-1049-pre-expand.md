SLOWRUN
Created: 2026-02-11

# Add Guidance for Slow Make Targets and Results File Usage

[DOCUMENTATION] Add explicit instructions to [improvement-planner.md](../../improvement-planner.md) and [CLAUDE.md](../../../CLAUDE.md) telling agents when to run slow `make rubyspec-*` targets versus when to read the existing results files.

## Goal Reference

[COMPLANG](../../goals/COMPLANG-compiler-advancement.md)

## Root Cause

The `make rubyspec-language` target compiles and runs 78 spec files sequentially (each with a 30-second timeout), taking many minutes to complete. It writes results to [docs/rubyspec_language.txt](../../rubyspec_language.txt) automatically via `tee`. A previous agent session ran this target multiple times: once to "inspect the output," then again piping it to the file -- not realizing the Makefile target already writes to that file. This wasted significant wall-clock time.

Neither [docs/improvement-planner.md](../../improvement-planner.md) nor [CLAUDE.md](../../../CLAUDE.md) documents that these targets are slow, that results files already exist and are readable, or that the targets should only be re-run to validate actual code changes. There is no guidance distinguishing "read the file to understand current state" from "run the target to validate a change."

## Infrastructure Cost

Zero. This edits two existing documentation files. No code, no build system changes.

## Prior Plans

- [PLANGUIDE](../archived/PLANGUIDE-add-improvement-planner-guidance/spec.md) -- IMPLEMENTED. Created `docs/improvement-planner.md`. That plan established the file but did not include guidance about slow targets or results file usage because the wasteful-rerun antipattern had not yet been observed. SLOWRUN adds a specific section to the file PLANGUIDE created, addressing a problem discovered after PLANGUIDE was implemented.

## Scope

**In scope:**
- Add a "Slow Targets and Results Files" section to [docs/improvement-planner.md](../../improvement-planner.md) explaining: which `make` targets are slow, that they automatically write to `docs/rubyspec_*.txt`, that agents should read those files for current state, and that re-running targets is only warranted to validate code changes
- Add a brief note to the Testing section of [CLAUDE.md](../../../CLAUDE.md) near the existing `make rubyspec-language` documentation, noting that these targets are slow and write to results files automatically

**Out of scope:**
- Changing any Makefile targets or build infrastructure
- Adding new results files or spec suites
- Modifying the run_rubyspec script

## Expected Payoff

- Eliminates multi-minute wasted runs where agents re-run `make rubyspec-*` just to read output that already exists in a file
- Prevents the specific antipattern of piping `make rubyspec-language` output to a file the target already writes to
- Saves significant wall-clock time per agent session (each `make rubyspec-language` run takes many minutes)
- Makes the "read file for state, run target for validation" distinction explicit and discoverable

## Proposed Approach

1. Add a section to [docs/improvement-planner.md](../../improvement-planner.md) after the "Test Infrastructure" section, titled something like "Slow Targets and Results Files," covering: the `make rubyspec-*` targets are slow (compiling+running dozens of specs), they automatically write to `docs/rubyspec_*.txt` via `tee`, read those files to understand current spec state, only re-run targets when validating actual code changes, never pipe target output to the results file (the target does this already).
2. Add a brief annotation in [CLAUDE.md](../../../CLAUDE.md) near the existing `make rubyspec-language` bullet in the Testing section, noting the slow runtime and automatic file output.

## Acceptance Criteria

- [ ] [docs/improvement-planner.md](../../improvement-planner.md) contains explicit guidance that `make rubyspec-*` targets are slow and should only be re-run to validate code changes, not to inspect current state
- [ ] [docs/improvement-planner.md](../../improvement-planner.md) states that results files (`docs/rubyspec_*.txt`) should be read directly when the agent needs to understand current spec status
- [ ] [docs/improvement-planner.md](../../improvement-planner.md) states that `make rubyspec-*` targets automatically write to `docs/rubyspec_*.txt` (so agents should never manually pipe output to those files)
- [ ] [CLAUDE.md](../../../CLAUDE.md) contains a note near the `make rubyspec-language` documentation that these targets are slow and write results to files automatically

---
*Status: APPROVED (implicit via --exec)*