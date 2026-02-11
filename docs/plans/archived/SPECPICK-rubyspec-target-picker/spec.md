SPECPICK
Created: 2026-02-10 21:45

# Rubyspec Target Picker Script

[TOOLING] Add a script that parses rubyspec results, ranks spec files by fix-ROI, and outputs a prioritized target for the investigate-spec skill -- enabling semi-automatic improvement cycles.

## Goal Reference

[COMPLANG](../../goals/COMPLANG-compiler-advancement.md)

## Root Cause

The existing improvement pipeline has a manual bottleneck at target selection. Three Claude Code skills exist for investigation, validation, and fixing ([investigate-spec](../../../.claude/skills/investigate-spec/SKILL.md), [validate-fix](../../../.claude/skills/validate-fix/SKILL.md), [fixtodo](../../../.claude/commands/fixtodo.md)), but they all require a human to choose which spec to work on. The [fixtodo](../../../.claude/commands/fixtodo.md) command picks from a manually curated TODO.md rather than from actual rubyspec results.

Meanwhile, [docs/rubyspec_language.txt](../../rubyspec_language.txt) contains machine-parseable data that already encodes ROI signals: files classified as CRASH but with high pass counts (e.g., `case_spec.rb`: 10 pass, 1 fail) are one fix away from PASS status, while zero-output crashes offer no leverage. No script currently extracts this ranking.

## Infrastructure Cost

Minimal. One Ruby script in [tools/](../../../tools/) that reads a text file and prints sorted output. No build system changes, no Docker dependencies, no external tools. Runs under MRI Ruby.

## Scope

**In scope:**
- A script (`tools/pick_rubyspec_target.rb`) that parses the output format of [run_rubyspec](../../../run_rubyspec) (from any results file, defaulting to `docs/rubyspec_language.txt`)
- Ranking logic that scores each spec file by proximity to full-pass (lowest `total - passed` first, excluding already-passing files and zero-output crashes)
- Output: the top-N ranked spec files with their current metrics and a one-line rationale (e.g., "1 failure from PASS", "high pass ratio with crash")
- A `--json` flag for machine-readable output that other tools or scripts can consume

**Out of scope:**
- Automatically invoking investigate-spec or any other skill
- Modifying run_rubyspec or rubyspec_helper.rb
- Building a full orchestration framework (that is a future plan under COMPLANG)
- Parsing GDB output, assembly, or anything beyond the results text file

## Expected Payoff

- Eliminates manual scanning of 78-line results files to find the best fix target
- Makes the "which spec should I work on next?" question answerable in one command
- The JSON output mode enables future automation (a wrapper script or skill that calls pick then investigate)
- Immediately usable by the fixtodo skill or a human operator to direct effort at highest-ROI specs

## Proposed Approach

Write `tools/pick_rubyspec_target.rb` that:
1. Reads a results file (argument or default path)
2. Parses each `[STATUS] path (P:X F:Y S:Z T:W)` line using a regex
3. Computes a priority score per file: primary sort by `(total - passed)` ascending (fewest failures first), secondary sort by `passed` descending (most evidence of working tests first), filtering out PASS files and files with T:0
4. Prints a ranked list (default top 10) with status, path, counts, and a short rationale
5. With `--json`, outputs the same data as a JSON array

## Prior Plans

- [DOCCLN](../archived/DOCCLN-doc-cleanup/spec.md) -- documentation cleanup, IMPLEMENTED. Unrelated to tooling or automation.
- No prior plans in the automation, tooling, or rubyspec target-selection area.

## Acceptance Criteria

- [ ] `ruby tools/pick_rubyspec_target.rb` (run from project root) parses the current `docs/rubyspec_language.txt` and prints a ranked list of spec files, with `case_spec.rb` (10 pass, 1 fail) appearing in the top 3
- [ ] `ruby tools/pick_rubyspec_target.rb --json` outputs valid JSON that can be parsed by another script
- [ ] Files with status PASS are excluded from the output; files with T:0 (zero test output) are ranked last or excluded
- [ ] The script accepts an optional file path argument to parse results from a different file (e.g., `docs/rubyspec_regexp.txt`)

## Open Questions

- Should the script also identify "near-PASS" crash files separately from high-failure files, or is a single unified ranking sufficient?

---
*Status: REJECTED — The focus on rubyspec_language.txt is flawed. Rubyspec_language.txt only tallies a very tiny subset of rubyspec. The plan needs an approach to running a broader, and broadening set of suites - e.g. maybe overnight, re-running a smaller subset (e.g the category being worked on) to prevent regressions - and picking from them. It is not necessary to rank the spec files. Just pick a spec file at random, run an explore step on that spec if one hasn't been done, and then create a plan for attempting to fix it. It's likely the runner, running --exec, should have a max time limit, and that the given plan should be deferred if it can't be addressed in that time (for manual restart). This plan aims far too small.*