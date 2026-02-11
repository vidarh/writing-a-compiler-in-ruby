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

## Implementation Details

### File 1: [docs/improvement-planner.md](../../improvement-planner.md)

**Insertion point:** After the "Test Infrastructure" section (line 18, after the `./run_rubyspec` paragraph) and before the "## Investigation Workflow" heading (line 20). Insert a new `## Slow Targets and Results Files` section between these two sections.

**Content to add — a new H2 section covering:**
- A table or list of the three slow `make` targets and their corresponding results files:
  - `make rubyspec-integer` → [docs/rubyspec_integer.txt](../../rubyspec_integer.txt)
  - `make rubyspec-regexp` → [docs/rubyspec_regexp.txt](../../rubyspec_regexp.txt)
  - `make rubyspec-language` → [docs/rubyspec_language.txt](../../rubyspec_language.txt)
- Each target compiles and runs dozens of spec files sequentially (each with a 30-second timeout), taking many minutes total
- Each target automatically writes output to its results file via `tee` (visible in [Makefile](../../../Makefile) lines 92, 96, 100)
- Clear guidance: **Read the `docs/rubyspec_*.txt` files** to understand current spec status — do NOT re-run the targets just to see results
- Clear guidance: **Only re-run** `make rubyspec-*` targets to validate actual code changes
- Explicit anti-pattern warning: never manually pipe target output to the results file (e.g., `make rubyspec-language > docs/rubyspec_language.txt`) — the target already does this via `tee`

**Follow the existing file's style:** short paragraphs, bold for emphasis, numbered/bulleted lists matching the style of the "Test Infrastructure" section above.

### File 2: [CLAUDE.md](../../../CLAUDE.md)

**Insertion point:** In the `### Testing` subsection (lines 170–176), after the three `make rubyspec-*` bullet points (lines 174–176) and before the `**Test Hierarchy:**` block (line 178). Insert a brief note paragraph.

**Content to add — a short paragraph or note covering:**
- These `make rubyspec-*` targets are slow (many minutes each)
- They automatically write results to `docs/rubyspec_*.txt` via `tee`
- Read those files for current state; only re-run targets to validate code changes

**Follow CLAUDE.md's existing style:** bold key phrases, concise bullet points, consistent with surrounding content.

### Patterns to Follow

- Both files use standard Markdown with `**bold**` for emphasis
- [docs/improvement-planner.md](../../improvement-planner.md) uses H2 (`##`) for top-level sections and numbered/bulleted lists
- [CLAUDE.md](../../../CLAUDE.md) uses H3 (`###`) for subsections within `## Build and Development Commands`, and `**bold:**` lead-ins for admonition blocks

### Edge Cases

- The file [docs/rubyspec_language_new.txt](../../rubyspec_language_new.txt) also exists but is not a standard results file from a Makefile target — do not reference it in the new guidance
- The `make spec` target (project-specific specs in `spec/`) is fast and does NOT have a results file — do not include it in the slow-targets guidance
- The `./run_rubyspec` command itself is documented separately in the Investigation Workflow section — the new guidance is specifically about the `make rubyspec-*` convenience targets

## Execution Steps

1. [ ] Add "Slow Targets and Results Files" section to [docs/improvement-planner.md](../../improvement-planner.md) — Insert a new `## Slow Targets and Results Files` section between the "## Test Infrastructure" section (after line 18) and the "## Investigation Workflow" section (line 20). Content: list the three slow targets and their results files, state that targets are slow, state that they auto-write via `tee`, instruct to read files for current state, instruct to only re-run for validation, warn against manually piping output to results files.

2. [ ] Add slow-target note to [CLAUDE.md](../../../CLAUDE.md) — Insert a brief note after the `make rubyspec-*` bullet points (after line 176) and before the `**Test Hierarchy:**` block (line 178). Content: note that these targets are slow (many minutes), auto-write to `docs/rubyspec_*.txt`, and should only be re-run to validate code changes (read the files for current state).

3. [ ] Verify acceptance criteria — Re-read both files to confirm all four acceptance criteria are met: (a) improvement-planner.md says targets are slow / only re-run for validation, (b) improvement-planner.md says to read results files for current state, (c) improvement-planner.md says targets auto-write to files (don't manually pipe), (d) CLAUDE.md has a note near the rubyspec targets about slow runtime and auto-file-output.

---
*Status: APPROVED (implicit via --exec)*