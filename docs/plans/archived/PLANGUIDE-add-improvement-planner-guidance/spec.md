PLANGUIDE
Created: 2026-02-11 00:08

# Add Improvement Planner Guidance to Compiler Project

> **User direction (2026-02-11 00:28):** The docs/improvement-planner.md file references files that are incomplete and 'manually' updated via makefile targets, and - in contradiction of the approved plan - directs the planner to a subset of specs. The plan also references bin/improve, which is not part of the project, and incorrectly prevents the plans from proposing changes to .claude -- the planner *IS FREE* to propose changes to the project specific .claude all it wants. The planner is also *incorrectly* being directed to not propose documentation-only plans. The DO propose section also *incorrectly* too strongly directs the planner to specific, limited types of fixes.

> **User direction (2026-02-11 00:16):** Rather than add this in README, which is targeted more toward humans, add an '@' reference to a separate file in docs/. Be cautious about referencing the existing skills, which are not particularly well tested - investigate them before making a decision.

[AUTOMATION] Create a dedicated guidance file in `docs/` and add an `@` reference to it from README.md, so the planner knows to pick random failing specs, run them live, and propose validated fixes.

## Goal Reference

[COMPLANG](../../goals/COMPLANG-compiler-advancement.md)

## Root Cause

The improvement planner reads README.md and CLAUDE.md when it runs in a project directory. The Desktop project exploits this with a "Do NOT propose" / "DO propose" section that steers the planner toward high-value work. The compiler project has no equivalent. Its CLAUDE.md covers coding rules and its README.md is targeted toward humans. Neither mentions the test infrastructure (`./run_rubyspec`, `make selftest`, `make selftest-c`). The planner has full tool access and can run any command, but without guidance it defaults to reading docs and proposing plans based on assumptions rather than live output. This is why five of six prior plans were rejected.

## Skill Investigation

The project has three existing skills (`investigate-spec`, `validate-fix`, `create-minimal-test`) defined in `.claude/skills/`. All three are well-documented but have **no evidence of actual testing or usage** — no execution logs, no git commits showing invocations, and prior exploration notes explicitly flag permission issues preventing autonomous execution. These skills should **not** be referenced in the guidance until they have been validated through real use. The guidance file should describe the workflow directly (run specs, analyze failures, propose fixes) rather than delegating to untested skills.

## Infrastructure Cost

Minimal. This creates one new file in `docs/` and adds a single `@` reference line to README.md. No code, no Makefile targets, no new tools.

## Prior Plans

- [SPECAUTO](../archived/SPECAUTO-enable-spec-driven-autonomous-fix-planning/spec.md) -- REJECTED after 3 revisions: "confused solutions that are pointlessly complicated and/or not generic enough." SPECAUTO bundled this guidance with Makefile targets for 5+ new suites, results file management, `rubyspec-refresh` with staleness checks, and COMPLANG goal updates. PLANGUIDE extracts only the planner guidance -- the one piece that directly addresses the planner's behavior -- and defers infrastructure to future plans.

## Scope

**In scope:**
- Create a new file `docs/improvement-planner.md` containing project-specific guidance for the improvement planner
- Add an `@docs/improvement-planner.md` reference to [README.md](../../../README.md) so the planner discovers it

**Out of scope:**
- Makefile targets (the runner already supports arbitrary directories; new targets are a separate plan)
- Generating or managing results files
- Updating the COMPLANG goal
- Fixing any specs
- Referencing the existing skills (untested; see Skill Investigation above)

## Expected Payoff

- Future planner invocations will run specs live before proposing, eliminating the "unvalidated" rejection pattern
- The planner will target substantive improvements instead of meta-automation (which has been repeatedly rejected)
- Follows a proven pattern already working in the Desktop project
- Keeps README.md human-focused while providing machine-readable guidance via `@` reference

## Proposed Approach

1. Create `docs/improvement-planner.md` containing: a brief note about the test infrastructure, instructions to pick a random spec and run it with `./run_rubyspec`, instructions to investigate failures and propose fix plans grounded in live output, and short "Do NOT propose" / "DO propose" lists tailored to compiler work.
2. Add a single `@docs/improvement-planner.md` reference line to README.md so the planner picks it up automatically.

## Acceptance Criteria

- [x] `docs/improvement-planner.md` exists with guidance for picking, running, and investigating specs before proposing fix plans
  VERIFIED: File exists (48 lines), contains Investigation Workflow (lines 20-28), Test Infrastructure (lines 6-18), Validation Requirements (lines 30-36), Do NOT/DO propose sections.
- [x] The file includes "Do NOT propose" guidance that excludes unvalidated fix proposals and automation-for-automation's-sake plans
  VERIFIED: Lines 38-43 list four prohibited categories including "not grounded in live spec output" and "automation-for-automation's-sake".
- [x] The file includes "DO propose" guidance that is broad and does not over-constrain the planner to specific fix types
  VERIFIED: Lines 45-48 say "Any improvement grounded in live test output and source analysis" — broad, not limited to specific fix types.
- [x] The file does NOT reference the existing skills (`investigate-spec`, `validate-fix`, `create-minimal-test`)
  VERIFIED: grep for all three strings returned no matches.
- [x] The file does NOT reference results files that are incomplete and manually updated via makefile targets
  VERIFIED: grep for `rubyspec_language.txt`, `rubyspec_integer.txt`, `rubyspec_regexp.txt` returned no matches.
- [x] The file does NOT direct the planner to only a subset of specs
  VERIFIED: Line 24 explicitly says "Do not limit yourself to any particular subdirectory." Lines 14-18 enumerate the full spec tree.
- [x] The file does NOT prohibit proposing changes to the project-specific `.claude`
  VERIFIED: grep for `.claude` returned no matches; no prohibitive language about `.claude` anywhere in the file.
- [x] The file does NOT prohibit documentation-only plans
  VERIFIED: grep for "documentation" (case-insensitive) returned no matches; no prohibitive language about documentation plans.
- [x] [README.md](../../../README.md) contains an `@docs/improvement-planner.md` reference
  VERIFIED: Line 17 of README.md contains exactly `@docs/improvement-planner.md` on its own line. git diff confirms only this line was added.
- [x] No other files are modified
  VERIFIED: git diff HEAD -- README.md shows only the `@` reference line added. docs/improvement-planner.md is a new untracked file. No other files were modified for this plan.

## Implementation Details

### File 1: `docs/improvement-planner.md` (NEW)

This is the main deliverable. It must follow the structural pattern established in the Desktop project's [README.md](../../../../Desktop/README.md):83-162 — an "Improvement Planner" heading followed by context, then "Do NOT propose" and "DO propose" subsections.

**Content to include:**

1. **Test infrastructure overview** — brief description of the test tiers and how to run them:
   - `make selftest` / `make selftest-c` — self-hosting validation (must pass before committing)
   - `./run_rubyspec <path>` — the universal spec runner ([run_rubyspec](../../run_rubyspec)), accepts individual files or directories
   - Available spec suites: `rubyspec/core/` has 50+ subdirectories (array, hash, string, kernel, etc.), `rubyspec/library/`, `rubyspec/command_line/`, plus `spec/` for project-specific tests
   - Do NOT reference results files (`rubyspec_language.txt`, etc.) — these are incomplete and manually updated via makefile targets; the planner should run specs live instead

2. **Investigation workflow** — step-by-step instructions for the planner:
   - Pick a spec file or directory (randomly from any part of the spec suite, not limited to specific subdirectories)
   - Run it live with `./run_rubyspec <path>` and examine the actual output
   - Identify the root cause of failures (compiler bug, missing library method, test framework limitation)
   - Check [docs/KNOWN_ISSUES.md](../KNOWN_ISSUES.md) and [docs/TODO.md](../TODO.md) for known context
   - Read relevant compiler source to understand the code path
   - Propose a fix plan grounded in the live output and source analysis

3. **"Do NOT propose" list** — tailored to the compiler project's rejection history (documented in [docs/improvement-planner-review.md](../improvement-planner-review.md)):
   - Fix proposals not grounded in live spec output (rejection pattern #3 from review)
   - Automation-for-automation's-sake / meta-infrastructure plans (rejection pattern #2)
   - Plans that modify rubyspec files (strict rule from [CLAUDE.md](../../CLAUDE.md))
   - Plans based on unverified assumptions about the execution environment
   - **Do NOT prohibit** changes to the project-specific `.claude` — the planner is free to propose those
   - **Do NOT prohibit** documentation-only plans — these are valid proposals

4. **"DO propose" list** — broad guidance aligned with the [COMPLANG goal](../goals/COMPLANG-compiler-advancement.md). The planner should have wide latitude to propose any improvement it identifies as valuable. Do NOT over-constrain this section to specific, limited types of fixes. The planner should feel free to propose:
   - Any improvement grounded in live test output and source analysis
   - Plans should include the specific spec file(s) tested, the command run, and the output observed when applicable

5. **Validation requirements** — every fix plan must:
   - Include `make selftest` and `make selftest-c` as verification steps
   - Re-run the target spec with `./run_rubyspec` to confirm the fix
   - Not regress other specs (run the relevant suite directory, not just the single file)

**Style/format notes:**
- Use markdown headers: `# Improvement Planner Guidance`, then `## ...` subsections
- Use `### Do NOT propose` and `### DO propose` (matching Desktop's heading level convention)
- Keep it concise — the Desktop version is ~80 lines for its planner section; aim for similar density
- Do NOT reference the skills `investigate-spec`, `validate-fix`, or `create-minimal-test` anywhere in the file

### File 2: [README.md](../../README.md) (EDIT — line 16 area)

Add a single `@docs/improvement-planner.md` reference line. The `@` prefix is the standard way to include referenced files in Claude Code's context loading.

**Placement:** After the existing Documentation bullet list (lines 10-15 of [README.md](../../README.md)), add the `@` reference on its own line. The reference should appear after the documentation section but before the "Status" section (line 17). This keeps the human-readable documentation list clean while ensuring the planner discovers the file.

**Exact format:** `@docs/improvement-planner.md` on a line by itself. No markdown formatting, no bullet point — just the bare `@` reference, matching the pattern used in other projects.

### Files NOT modified

Per acceptance criteria, no changes to:
- [Makefile](../../Makefile)
- Any file in `.claude/skills/`
- Any file in `rubyspec/`
- [docs/goals/COMPLANG-compiler-advancement.md](../goals/COMPLANG-compiler-advancement.md)

## Execution Steps

1. [ ] Create `docs/improvement-planner.md` — Write the new guidance file with all five content sections described above: test infrastructure overview, investigation workflow, "Do NOT propose" list, "DO propose" list, and validation requirements. Keep total length under ~80 lines. Do not reference the existing skills. Do not reference results files. Do not direct the planner to only a subset of specs. Do not prohibit `.claude` changes or documentation-only plans. Keep the "DO propose" section broad.

2. [ ] Add `@docs/improvement-planner.md` to [README.md](../../README.md) — Insert the bare `@` reference on a new line after line 15 (the last documentation bullet) and before line 17 (the blank line before "## Status"). This is a one-line insertion.

3. [ ] Verify acceptance criteria — Confirm:
   - `docs/improvement-planner.md` exists and contains all required sections
   - The file includes "Do NOT propose" guidance
   - The file includes "DO propose" guidance (broad, not over-constrained)
   - The file does NOT contain the strings `investigate-spec`, `validate-fix`, or `create-minimal-test`
   - The file does NOT reference results files (`rubyspec_language.txt`, etc.)
   - The file does NOT direct the planner to only a subset of specs
   - The file does NOT prohibit `.claude` changes
   - The file does NOT prohibit documentation-only plans
   - The file does NOT reference `bin/improve`
   - [README.md](../../README.md) contains the line `@docs/improvement-planner.md`
   - No other files were modified (check with `git diff --name-only`)

---
*Status: IMPLEMENTED*