SPECAUTO
Created: 2026-02-10 23:42

# Enable Spec-Driven Autonomous Fix Planning

[AUTOMATION] Grant the improvement planner Bash access to compiler test commands so it can pick random failing specs, run them, investigate failures, and generate validated fix plans -- closing the autonomous improvement loop.

## Goal Reference

[COMPLANG](../../goals/COMPLANG-compiler-advancement.md)

## Root Cause

The improvement planner runs daily via cron (`bin/improve --create`) but is restricted to `Bash(mkdir:*)` -- it cannot execute `./run_rubyspec`, `make selftest`, `./compile`, or any other command. This means it cannot:

1. **Pick and run a failing spec** to get fresh diagnostic output
2. **Validate premises** before proposing fixes (the CASEFIX rejection cited this: "run_rubyspec wasn't run")
3. **Investigate crash causes** by compiling minimal reproductions or running GDB

The planner can read static results files ([rubyspec_language.txt](../../rubyspec_language.txt)) but cannot interact with the compiler. It is forced to propose plans based on stale documentation rather than live test output. This is why every fix plan proposed so far has been rejected as "unvalidated" or "wrong focus" -- the planner literally cannot validate anything.

The explore agent has similar restrictions (`Bash(ls:*)`, `Bash(wc:*)`, `Bash(git log:*)`, `Bash(git show:*)`) and also cannot run specs.

Meanwhile, the existing skills ([investigate-spec](../../../.claude/skills/investigate-spec/SKILL.md), [validate-fix](../../../.claude/skills/validate-fix/SKILL.md)) document exactly how to investigate and validate spec failures, but neither the planner nor the explorer can execute the commands these skills describe.

The root cause is a tooling permission gap: the autonomous agents have the knowledge (exploration notes, skills, CLAUDE.md) and the test infrastructure (run_rubyspec, Docker, selftest) but lack permission to connect the two.

## Infrastructure Cost

Low. This modifies [bin/improve](../../../../bin/improve) in the Desktop project (one file, ~5 lines changed for tool permissions, plus ~20 lines of compiler-specific planner instructions). No new scripts, no new cron entries, no new tools. The compiler's test infrastructure already exists and works.

## Prior Plans

- [SPECPICK](../archived/SPECPICK-rubyspec-target-picker/spec.md) -- REJECTED: "aims far too small" and "just focus on rubyspec_language.txt." SPECPICK proposed a ranking script (new tooling) that the planner would still not be able to run. SPECAUTO addresses this by giving the planner direct Bash access so it can run specs itself -- no intermediate tooling needed.

- [SPECWIDE](../archived/SPECWIDE-broad-rubyspec-baseline/spec.md) -- REJECTED: "ignored the feedback to reuse the improvement planner and instead suggested building a separate infrastructure." SPECWIDE proposed a new `/fixspec` command as a parallel automation system. SPECAUTO does the opposite: it enhances the existing improvement planner so IT becomes the autonomous fix cycle, with no new commands or scripts.

- [CASEFIX](../archived/CASEFIX-fix-case-spec-crash/spec.md) -- REJECTED: "hasn't been validated. run_rubyspec wasn't run. Wrong focus to create individual plans for unvalidated problems instead of addressing automation." SPECAUTO directly addresses this: once the planner can run specs, every future fix plan will be validated before it is proposed.

- [NOPARENS](../archived/NOPARENS-fix-noparens-default-block-segfault/spec.md) -- REJECTED: "Wrong focus to do this rather than improve automation of fixes." SPECAUTO IS the automation improvement that enables future fix plans to be generated automatically.

## Scope

**In scope:**
- Expand the planner's `allowed_tools` in [bin/improve](../../../../bin/improve) (line ~2346) to include compiler test commands when `target_dir` matches the compiler project: `./run_rubyspec`, `make selftest`, `make selftest-c`, `./compile`, `./compile2`, `gdb`
- Expand the explore agent's `allowed_tools` (line ~559) similarly for the compiler
- Add compiler-specific instructions to the planner prompt (injected when `target_dir` is the compiler) telling it to: pick a random non-passing spec from [rubyspec_language.txt](../../rubyspec_language.txt), run it, analyze the output, and generate a fix plan based on the findings
- Add a `make rubyspec-refresh` target to the compiler's [Makefile](../../../Makefile) that runs `make rubyspec-language` only if results are older than 24 hours (so the planner can trigger a refresh without redundant runs)

**Out of scope:**
- Building new tooling, scripts, or commands (no `/fixspec`, no `pick_rubyspec_target.rb`)
- Changing the planner's core architecture or adding new agent modes
- Actually fixing any specs (that will be done by future plans that THIS enables)
- Expanding to core/ suites (future plan under COMPLANG once language/ automation is proven)

## Expected Payoff

- Every future compiler improvement plan will be validated against live spec output before being proposed -- eliminating the "unvalidated" rejection pattern
- The planner becomes the autonomous fix cycle: each daily invocation picks a random failing spec, investigates it, and produces a ready-to-execute fix plan
- No new infrastructure to maintain -- reuses existing `bin/improve`, existing skills, existing test commands
- Unblocks the entire COMPLANG goal: with ~70 non-passing specs and daily planner invocations, the pipeline can systematically address one spec per day

## Proposed Approach

1. In [bin/improve](../../../../bin/improve), detect when `target_dir` is the compiler project (by checking for `CLAUDE.md` containing "Ruby compiler" or by path match)
2. When targeting the compiler, expand `allowed_tools` for both the explore and create agents to include `Bash(./run_rubyspec:*)`, `Bash(make:*)`, `Bash(./compile:*)`, `Bash(gdb:*)`
3. Inject compiler-specific planner instructions: "Pick a random non-passing spec from `docs/rubyspec_language.txt`, run it with `./run_rubyspec`, analyze the output, and propose a fix plan based on what you find"
4. Add `rubyspec-refresh` Makefile target for conditional results refresh

## Acceptance Criteria

- [ ] When `bin/improve --create --dir ~/Desktop/Projects/Compiler` runs, the planner agent can execute `./run_rubyspec rubyspec/language/SPEC.rb` and `make selftest` (verified by checking the agent's output log shows spec execution output)
- [ ] The planner's prompt, when targeting the compiler, includes instructions to pick a random non-passing spec and investigate it before proposing
- [ ] A test invocation of the planner against the compiler produces a plan that references specific spec output from an actual run (not just from the static results file)
- [ ] `make selftest` and `make selftest-c` still pass (no compiler changes in this plan)

## Open Questions

- Should the tool permissions be project-specific (detected by path or CLAUDE.md content) or controlled by a per-project config file (e.g., `docs/improve.yaml`)?
- Should the planner also be able to run `make rubyspec-language` to refresh the full results, or should it only run individual specs?

---
*Status: PROPOSAL - Awaiting approval*
