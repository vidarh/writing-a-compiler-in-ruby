# Improvement Planner Review

*Last updated: 2026-02-11*

## Statistics

| Metric | Count |
|--------|-------|
| Total plans | 11 |
| Implemented | 4 (DOCCLN, PLANGUIDE, SLOWRUN, HEREDOCESC) |
| Rejected | 5 (SPECPICK, SPECWIDE, CASEFIX, NOPARENS, SPECAUTO) |
| Active | 2 (GITCLEAN, BOOLOPS) |
| Deferred | 0 |
| Goals | 1 (COMPLANG) |

**Success rate**: 44% (4 of 9 resolved plans reached implementation).

**Rejection rate**: 56% of resolved plans — all five rejected plans were from
the same session (2026-02-10) and all related to the COMPLANG goal of
autonomous spec progression. No plans have been rejected since.

**Plan diversity**: The pipeline has moved beyond documentation-only work.
HEREDOCESC was the first compiler-modifying plan to reach implementation,
and BOOLOPS (active) targets core library changes. GITCLEAN addresses
repository hygiene.

**Revision cycles**: SPECAUTO went through 3 revision rounds before rejection.
HEREDOCESC required extensive iteration (7+ stopped/failed execution attempts,
12 spec snapshots) before being completed manually. PLANGUIDE needed one
corrective iteration. DOCCLN and SLOWRUN executed cleanly on first attempt.

## Rejection Patterns

Five of eleven plans were rejected, all from the initial session (2026-02-10).
No rejections have occurred since, suggesting the early lessons were absorbed.
Three distinct patterns emerged:

### 1. Point Solutions Instead of Automation (CASEFIX, NOPARENS)

Both plans proposed fixing individual compiler bugs (case statement crash,
no-parens method call segfault). The user explicitly wanted plans that
improve the *automation pipeline* for fixing many bugs, not plans that fix
one bug at a time. NOPARENS was technically well-written with validated root
cause analysis, but strategically misaligned. CASEFIX compounded this by
not even validating the problem first.

**Lesson**: When a goal is about *process improvement* (autonomous spec
progression), plans must target the process, not individual instances. The
planner needs to distinguish between "fix a bug" and "build machinery to
fix bugs."

### 2. Building Parallel Infrastructure Instead of Reusing Existing (SPECWIDE, SPECAUTO)

SPECWIDE proposed a new `/fixspec` command. SPECAUTO went through 3 revision
cycles but kept proposing overly complex or narrow solutions. Both were told
to reuse the existing improvement planner infrastructure. SPECWIDE ignored
this constraint entirely. SPECAUTO tried to address it but each revision
introduced new problems (false assumptions about tool access, project-specific
edits to shared tooling, narrow focus on one suite).

**Lesson**: The planner must respect architectural constraints about *where*
solutions live. "Reuse existing infrastructure" is a hard requirement, not a
suggestion.

### 3. Insufficient Validation Before Planning (CASEFIX, SPECPICK)

CASEFIX proposed fixing a crash without running the spec to understand the
actual failure. SPECPICK focused exclusively on `rubyspec_language.txt` (78
files) without recognizing this was a tiny subset of the full rubyspec suite.
Both plans were built on incomplete understanding of the problem space.

**Lesson**: Plans must be grounded in actual investigation, not assumptions.
The planner should run relevant commands and examine real output before
proposing solutions.

## Success Patterns

Four plans have been implemented, spanning documentation, tooling guidance,
and compiler modification. Patterns that predict success:

### 1. Clean Execution Plans (DOCCLN, SLOWRUN)

Both executed cleanly on first attempt with no revisions:

- **DOCCLN** (228 lines): Documentation cleanup with file-by-file deletion
  rationale, line-by-line edit instructions. Accepted on first submission,
  executed in 16 minutes, all 6 criteria verified.
- **SLOWRUN** (107 lines): Targeted documentation additions addressing a
  specific observed antipattern (re-running slow make targets). All 4
  criteria verified on first attempt.

**Common traits**: Well-scoped, zero-risk to compiler functionality,
detailed implementation guidance, verifiable outcomes.

### 2. Plans Requiring Corrective Iteration (PLANGUIDE)

PLANGUIDE (161 lines) needed one corrective cycle — the initial execution
contradicted the approved spec (referenced incomplete results files,
restricted planner too aggressively). The spec was correct; the agent
deviated. Re-execution passed all 9 criteria.

**Pattern**: When the spec is clear but the execution agent introduces
errors, the feedback loop works — specific issues are identified, the spec
remains authoritative, and the re-execution converges.

### 3. Plans Requiring Manual Completion (HEREDOCESC)

HEREDOCESC (155 lines) is the most complex implemented plan and the first
to modify compiler code. It required 7+ stopped/failed execution attempts
over several hours before being completed manually. The agent repeatedly
attempted approaches that were explicitly rejected in the plan document
(pre-reading heredoc bodies into buffers, using unget for modified content,
duplicating escape handling).

**Pattern**: For plans requiring deep architectural understanding, the
execution agent may fail to follow constraints even when they are spelled
out. Manual intervention was necessary. The plan document itself evolved
into valuable documentation of both correct and incorrect approaches.

### Implemented Plan Size Distribution

| Plan | Lines | Execution | Criteria |
|------|-------|-----------|----------|
| DOCCLN | 228 | Clean | 6/6 |
| PLANGUIDE | 161 | 1 correction | 9/9 |
| HEREDOCESC | 155 | Manual completion | 9/10 (1 FAIL: external cause) |
| SLOWRUN | 107 | Clean | 4/4 |

**Contrast with rejected plans**: Rejected plans averaged 69–134 lines.
Implemented plans average 163 lines. But size alone does not explain
success — strategic alignment and execution-level detail are the
discriminating factors.

## Execution Quality

### Tier 1 — Clean Execution: DOCCLN, SLOWRUN

**DOCCLN**: Created at 17:33, verified at 17:49 (16 minutes). All 6
acceptance criteria passed. No revisions, no regressions. The benchmark
for execution quality.

**SLOWRUN**: Single execution attempt, all 4 criteria verified. 2 snapshots
(pre-expand, post-exec) — the ideal audit trail.

Both were documentation-only plans with zero compiler risk.

### Tier 2 — Corrective Iteration: PLANGUIDE

PLANGUIDE required one re-execution. The initial implementation (00:20)
deviated from the approved spec in multiple ways: referenced incomplete
results files, directed planner to a subset of specs, incorrectly prohibited
`.claude` changes and documentation-only plans. The spec was correct — the
execution agent introduced errors not present in the plan.

After user feedback identifying the specific issues, re-execution (00:29)
passed all 9 criteria. The correction cycle took ~14 minutes and the
feedback mechanism worked as designed: spec remained authoritative, agent
fixed its own deviations.

**Pattern**: The execution agent can introduce errors that contradict an
approved spec. A single feedback round is sufficient to correct this when
the spec clearly specifies the expected behavior.

### Tier 3 — Catastrophic Execution: HEREDOCESC

HEREDOCESC is the pipeline's most significant execution failure. The plan
was well-written (155 lines, clear architectural constraints, explicit
lists of rejected approaches) but the execution agent could not follow it.

**Timeline of failed attempts** (7+ stops over ~3 hours):

- 07:05 — First execution launched
- 07:24, 07:27, 07:29, 07:36, 07:40, 07:44 — Five consecutive feedback/stop
  cycles in 20 minutes. The agent repeatedly attempted explicitly rejected
  approaches: pre-reading heredoc bodies into buffers, using unget for
  modified content, duplicating escape handling instead of reusing quoted
  string infrastructure.
- 07:45 — Second execution attempt launched
- 08:03 — Post-exec snapshot, but verification failed
- 08:49 — Third execution attempt launched
- 09:27 — Post-exec snapshot, but still failing
- 09:53, 10:01 — More feedback cycles
- 10:02 — Fourth execution attempt
- 10:54 — Final post-exec snapshot

The plan accumulated 12 spec snapshots (1 pre-expand, 7 pre-feedback,
3 post-exec, 1 pre-feedback late). The implementation was ultimately
completed manually. The "regression" in acceptance criteria (overall pass
count dropping from 272 to 269) was caused by upstream rubyspec changes
between planning and execution, not by the implementation.

**Root cause of execution failure**: The plan required the agent to
understand an architectural invariant (heredocs must reuse the scanner's
quoted string infrastructure, reading character-by-character) and implement
accordingly. The agent could not internalize this constraint despite
explicit documentation and repeated corrections. Each attempt fell back to
one of the prohibited buffer-based approaches.

**Lesson for acceptance criteria**: The HEREDOCESC "regression" flag was
caused by external test suite changes, not implementation bugs. Future
plans should avoid hard-coding expected pass counts, or should specify
that counts can be revalidated by re-running tests against HEAD.

### Tier 4 — Never Reached Execution: SPECPICK, SPECWIDE, CASEFIX, NOPARENS

All four were rejected immediately (single log entry each). Fast, clear
rejections — preferable to plans that waste revision cycles.

### Tier 5 — Failed Revision Cycle: SPECAUTO

SPECAUTO went through 3 revision rounds over ~13 minutes before final
rejection:

1. **Rev 1** (23:45): Rejected for false premise — assumed improvement agent
   has limited tool access.
2. **Rev 2** (23:49): Rejected for proposing edits to `bin/improve` — a
   shared tool that must not be modified per-project.
3. **Rev 3** (23:54): Rejected for being too narrow — focused on
   `rubyspec_language.txt` when the requirement was *all* suites.
4. **Final rejection** (23:58): "confused solutions that are pointlessly
   complicated and/or not generic enough."

Each revision fixed the specific complaint but introduced a new category of
error — patch-and-pray rather than understand-then-design.

### Spec Snapshot Summary

| Plan | Snapshots | Breakdown | Interpretation |
|------|-----------|-----------|----------------|
| HEREDOCESC | 12 | 1 pre-expand, 8 pre-feedback, 3 post-exec | Extreme churn — catastrophic execution |
| PLANGUIDE | 5 | 1 pre-expand, 2 pre-feedback, 2 post-exec | Corrective iteration — acceptable |
| SPECAUTO | 3 | All pre-revise | Churn without progress |
| DOCCLN | 2 | pre-expand + post-exec | Clean audit trail |
| SLOWRUN | 2 | pre-expand + post-exec | Clean audit trail |
| GITCLEAN | 1 | pre-revise | Active plan, awaiting approval |
| Others | 0 | — | Rejected before artifacts |

## Plan Document Health

With 2 active plans and 9 archived, document health is a mix of
retrospective analysis and forward-looking assessment.

### Structural Completeness

All plans include the required sections (Root Cause, Infrastructure Cost,
Scope, Expected Payoff, Proposed Approach, Acceptance Criteria). Template
enforcement is working consistently — no plans have been rejected for
missing sections.

**Notable gap**: Neither active plan (GITCLEAN, BOOLOPS) has a Prior Plans
section. BOOLOPS has a Goal Reference to COMPLANG; GITCLEAN has none. For
GITCLEAN this is appropriate (repository hygiene is unrelated to prior
work), but BOOLOPS could benefit from referencing prior compiler-modifying
plans (HEREDOCESC) for execution pattern guidance.

### Prior Plans References

Cross-referencing works well in the archived plans:
- SPECWIDE → SPECPICK (detailed diff analysis)
- CASEFIX → SPECPICK, SPECWIDE
- NOPARENS → SPECPICK, SPECWIDE, CASEFIX
- SPECAUTO → SPECPICK, SPECWIDE, CASEFIX, NOPARENS
- PLANGUIDE → SPECAUTO (extracted working subset from rejected plan)
- SLOWRUN → PLANGUIDE (augments file PLANGUIDE created)

The planner correctly *sees* prior rejections but historically failed to
*learn* from them strategically. The later plans (PLANGUIDE, SLOWRUN)
show improvement — PLANGUIDE explicitly extracted the viable subset from
the rejected SPECAUTO.

### Document Size Distribution

| Plan | Lines | Outcome |
|------|-------|---------|
| DOCCLN | 228 | Implemented |
| PLANGUIDE | 161 | Implemented (1 correction) |
| HEREDOCESC | 155 | Implemented (manual) |
| SPECAUTO | 134 | Rejected (3 revisions) |
| SLOWRUN | 107 | Implemented |
| GITCLEAN | 106 | Active |
| SPECWIDE | 83 | Rejected |
| NOPARENS | 77 | Rejected |
| BOOLOPS | 73 | Active |
| CASEFIX | 72 | Rejected |
| SPECPICK | 69 | Rejected |

Implemented plans average 163 lines; rejected plans average 87 lines. The
active plans (106 and 73 lines) are on the smaller side — BOOLOPS in
particular may need more implementation detail for clean execution,
especially given the open question about `Object#__true?` return values.

### Active Plan Assessment

**GITCLEAN** (106 lines): Well-structured with 3 clear phases, 8 acceptance
criteria, and correct handling of the bootstrapping problem (dirty state
already on master). One revision already requested and incorporated
regarding rubyspec submodule hygiene. Ready for approval per assessment.

**BOOLOPS** (73 lines): Solid root cause analysis backed by live spec
execution. The open question (Ruby `true` vs low-level `%s(sexp 1)` for
`Object#__true?`) should be resolved before execution — this is exactly
the kind of ambiguity that causes execution failures. At 73 lines, this
is the shortest plan to be approved (if approved), and given HEREDOCESC's
execution struggles with compiler modifications, additional implementation
detail would reduce risk.

### Spec Snapshot Churn

HEREDOCESC dominates the snapshot count with 12 snapshots — nearly as many
as all other plans combined (13 across the remaining 10 plans). This is a
red flag for execution quality, not plan quality. In a healthy pipeline,
most snapshots should be post-exec, not pre-feedback. Current distribution:

- Pre-expand: 4 (DOCCLN, SLOWRUN, PLANGUIDE, HEREDOCESC) — healthy
- Post-exec: 7 (DOCCLN, SLOWRUN, HEREDOCESC×3, PLANGUIDE×2) — healthy
- Pre-feedback: 10 (HEREDOCESC×8, PLANGUIDE×2) — execution churn
- Pre-revise: 4 (SPECAUTO×3, GITCLEAN×1) — planning churn

Total: 25 spec snapshots across all plans (HEREDOCESC accounts for 48%).

## What Has Improved

Comparing against the first review baseline (6 plans, 17% success rate):

### Plan Quality and Strategic Alignment

- **Success rate**: 17% → 44% of resolved plans. The planner has learned
  to propose strategically aligned work after the initial batch of
  rejections.
- **Zero new rejections**: All 5 plans since the initial rejection batch
  have been approved or are active. The planner stopped proposing point
  solutions for automation problems.
- **Plan diversity**: Moved beyond documentation-only work. HEREDOCESC
  modified compiler code; BOOLOPS targets core library changes.
  PLANGUIDE and SLOWRUN addressed tooling guidance. GITCLEAN addresses
  repository hygiene.

### Cross-Referencing and Learning

- **PLANGUIDE** successfully extracted the viable subset from the rejected
  SPECAUTO plan — evidence that the planner can learn from rejections at
  a strategic level, not just avoid the specific complaint.
- **SLOWRUN** correctly built incrementally on PLANGUIDE rather than
  starting fresh — the "augment, don't replace" pattern is working.

### Execution Pipeline

- **Clean execution** demonstrated for documentation plans (DOCCLN,
  SLOWRUN) and guidance plans (PLANGUIDE after correction).
- **Corrective feedback loop** works for spec-agent deviations (PLANGUIDE).
- **Compiler-modifying execution** remains problematic (HEREDOCESC required
  manual completion after 7+ failed attempts).

### Metrics Comparison

| Metric | First Review | Current |
|--------|-------------|---------|
| Success rate | 17% (1/6) | 44% (4/9 resolved) |
| Rejection rate | 83% | 56% (all from initial session) |
| Clean executions | 1 (DOCCLN) | 2 (DOCCLN, SLOWRUN) |
| Corrective iterations | 0 | 1 (PLANGUIDE) |
| Manual completions | 0 | 1 (HEREDOCESC) |
| Execution regressions | 0 | 0 (HEREDOCESC "regression" was external) |

## Remaining Root Causes

### 1. Execution Agent Cannot Follow Architectural Constraints (Critical)

**Elevated from new evidence.** HEREDOCESC is the clearest case: the plan
explicitly documented rejected approaches (buffer pre-reading, unget
modification, duplicated escape handling) and the required approach (reuse
quoted string infrastructure, read character-by-character from scanner).
The execution agent attempted the rejected approaches 7+ times across
multiple execution cycles.

This is not a planning failure — the plan was clear and correct. It is an
execution agent failure to internalize and follow constraints that require
deep understanding of the codebase architecture.

**Risk**: As the pipeline moves from documentation plans to compiler-
modifying plans, this becomes the dominant bottleneck. BOOLOPS (active) will
be the next test case — it requires core library changes with specific
implementation patterns.

**Evidence**: HEREDOCESC (12 snapshots, manual completion). Also PLANGUIDE
(agent deviated from approved spec on first execution).

### 2. Strategic Misalignment (Improved — was Critical, now Low)

Previously the dominant failure mode (all 5 rejections). No new evidence
since the initial session. PLANGUIDE, SLOWRUN, HEREDOCESC, GITCLEAN, and
BOOLOPS are all strategically aligned. The planner has stopped proposing
point solutions for automation problems.

**Residual risk**: The COMPLANG goal's "Potential Plans" section still lists
tactical items that could re-trigger this pattern. But recent plans suggest
the planner has internalized the lesson.

### 3. Hard-Coded Acceptance Criteria Fragility (New — Moderate)

HEREDOCESC's acceptance criteria included a specific expected pass count
(272). When upstream rubyspec changes altered the test pool between planning
and execution, this criterion became unfalsifiable — the implementation was
correct but the count didn't match. The plan was marked IMPLEMENTED with a
FAIL note and an exemption.

**Root cause**: Plans that specify exact numerical outcomes are brittle when
the underlying test suite changes. This is particularly relevant for a
project that tracks an evolving external spec suite.

**Evidence**: HEREDOCESC criterion failure (272 → 269 due to hash_spec.rb
test pool change).

### 4. Failure to Verify Assumptions (Improved — was Moderate, now Low)

No new evidence of assumption failures in recent plans. BOOLOPS includes
live spec execution output in its root cause analysis. GITCLEAN correctly
assessed the bootstrapping constraint (can't branch from dirty master).

**Historical evidence** remains: SPECAUTO (false premise about tool access),
CASEFIX (unvalidated crash), SPECPICK (incomplete scope).

### 5. Inability to Learn From Revision Feedback (Stable — Moderate)

No new positive or negative evidence. SPECAUTO remains the only case of
multi-round revision failure. GITCLEAN had one revision request that was
successfully incorporated, but this is insufficient to declare the pattern
resolved.

### 6. Architectural Boundary Blindness (Improved — was Low-Moderate, now Low)

No new violations. PLANGUIDE and SLOWRUN correctly targeted project-local
documentation without touching shared tooling. GITCLEAN correctly limits
itself to git operations and project-local policy documents.

**Historical evidence**: SPECWIDE (new `/fixspec` command), SPECAUTO
(`bin/improve` edits).

## Proposed Adjustments

### A1. Require Investigation Before Planning (addresses Root Cause #4)

The planner should be required to run relevant commands (specs, tests, tool
inspection) and include actual output in the plan before proposing solutions.
Plans built on assumptions without evidence should be rejected at template
validation, not at user review.

**Status**: Partially addressed. BOOLOPS includes live spec execution output
in its root cause analysis, showing the planner can do this when prompted.
Not yet a systematic requirement. No new assumption failures observed.

### A2. Clarify Strategic vs. Tactical Scope in Goals (addresses Root Cause #2)

The COMPLANG goal's "Potential Plans" section lists tactical items ("fix
specific crashing spec files"). This actively encourages the point-solution
approach the user rejects.

**Status**: Partially addressed by practice — the planner has stopped
proposing point solutions. The goal text itself has not been updated, so
the risk of regression remains if the planner loses context.

### A3. Document Architectural Boundaries (addresses Root Cause #6)

The COMPLANG goal or the plan template should explicitly list what components
the planner may and may not modify.

**Status**: Partially addressed. PLANGUIDE created guidance documentation
that implicitly covers some boundaries. No new boundary violations observed.
Explicit boundary list not yet formalized.

### A4. Cap Revision Cycles (addresses Root Cause #5)

SPECAUTO went through 3 revisions without converging. Consider a hard cap
of 2 revision rounds.

**Status**: Not tested. No plans have entered multi-round revision since
SPECAUTO. GITCLEAN had one revision that was successfully incorporated.
The cap remains a reasonable safeguard if the pattern recurs.

### A5. Create LESSONS.md for Rejection Pattern Persistence

Give the planner explicit access to rejection history to reduce repeated
strategic errors.

**Status**: Not yet implemented. The `docs/plans/archived/LESSONS.md` path
is designated but the file does not exist. The rejection patterns are
documented in this review but not in a planner-accessible format.

### A6. Avoid Hard-Coded Numerical Acceptance Criteria (NEW — addresses Root Cause #3)

Plans should not specify exact expected pass counts when the test suite may
change between planning and execution. Instead, criteria should either:
- Specify directional improvements ("heredoc_spec pass count increases")
- Allow revalidation by re-running tests against HEAD
- Use relative rather than absolute thresholds

**Evidence**: HEREDOCESC criterion failure due to upstream rubyspec changes.

**Status**: Not yet implemented. BOOLOPS (active) specifies concrete pass
rate improvements by file — these should be validated as directional, not
absolute, to avoid the same problem.

### A7. Increase Execution Detail for Compiler-Modifying Plans (NEW — addresses Root Cause #1)

Plans that modify compiler code or core libraries need significantly more
implementation detail than documentation plans. HEREDOCESC's execution
failures demonstrate that even explicit lists of rejected approaches are
insufficient — the execution agent needs step-by-step implementation
guidance at the code level, not just architectural constraints.

For compiler-modifying plans, consider requiring:
- Specific file paths and functions to modify
- Code-level implementation sketches (pseudocode or actual diffs)
- Explicit test commands to run at each step
- "If you find yourself doing X, stop — the correct approach is Y" guardrails

**Evidence**: HEREDOCESC (7+ failed attempts despite clear constraints).
BOOLOPS is the next test case for this pattern.

**Status**: Not yet implemented.
