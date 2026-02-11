DOCCLN
Created: 2026-02-10 17:33

# Documentation Cleanup and Archival

[CLEANUP] Remove obsolete docs, archive completed plans, and update stale status data in KNOWN_ISSUES.md and TODO.md.

## Goal Reference

None -- this is standalone housekeeping that benefits all future work.

## Root Cause

Documentation has accumulated organically over months of development sessions.
Each session produced investigation logs, migration plans, and status documents
that were valuable at the time but have since been superseded:

- **Completed plans stay forever**: [KERNEL_MIGRATION_PLAN.md](docs/KERNEL_MIGRATION_PLAN.md) and
  [INVESTIGATION_POSTFIX_IF_BUG.md](docs/INVESTIGATION_POSTFIX_IF_BUG.md) document
  work that is done, but remain as if active.
- **Redundant content is never pruned**: [DEVELOPMENT_RULES.md](docs/DEVELOPMENT_RULES.md) (18 lines)
  duplicates rules already in CLAUDE.md. [REJECTED_APPROACH_METHOD_CHAINING.md](docs/REJECTED_APPROACH_METHOD_CHAINING.md)
  lessons are captured in [control_flow_as_expressions.md](docs/control_flow_as_expressions.md).
- **Status data rots**: [TODO.md](docs/TODO.md) and [KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md) say
  "3/78 passing (4%)" but current `rubyspec_language.txt` shows substantially different results.
  [RUBYSPEC_CRASH_ANALYSIS.md](docs/RUBYSPEC_CRASH_ANALYSIS.md) categorizes 50 crashes from 2025-11-26
  that no longer match reality.
- **Session logs masquerade as references**: [bignums.md](docs/bignums.md) is 1679 lines because
  it includes every debugging session, hypothesis, and failed attempt for a feature
  that is now complete across all 9 phases.

The root cause is simply the absence of a periodic cleanup pass. There is no
structural issue preventing cleanup -- all files are committed in git history.

## Infrastructure Cost

Zero. This plan touches only markdown files in docs/. No code changes, no build
system changes, no integration with external tools. The only tool required is
`git rm` and a text editor.

## Scope

**In scope:**

1. `git rm` six obsolete files (all previously committed, retained in history):
   - [DEVELOPMENT_RULES.md](docs/DEVELOPMENT_RULES.md) -- entirely redundant with CLAUDE.md
   - [RUBYSPEC_INTEGRATION.md](docs/RUBYSPEC_INTEGRATION.md) -- proposal fully implemented, runner exists
   - [INVESTIGATION_POSTFIX_IF_BUG.md](docs/INVESTIGATION_POSTFIX_IF_BUG.md) -- resolved (commit f00b850), no remaining work
   - [RUBYSPEC_CRASH_ANALYSIS.md](docs/RUBYSPEC_CRASH_ANALYSIS.md) -- data from 2025-11-26, categories no longer match reality
   - [REJECTED_APPROACH_METHOD_CHAINING.md](docs/REJECTED_APPROACH_METHOD_CHAINING.md) -- lessons captured in [control_flow_as_expressions.md](docs/control_flow_as_expressions.md)
   - [KERNEL_MIGRATION_PLAN.md](docs/KERNEL_MIGRATION_PLAN.md) -- plan complete (Phases 1-2 done, puts decided, raise migrated); only deferred Enumerable remains (tracked in TODO)

2. Clean [KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md):
   - Remove FIXED issues 1 ("super() Uses Wrong Superclass") and 3 ("Classes in Lambdas") from Active Issues section
   - Keep brief mention in "Recent Fixes" section
   - Update spec pass/fail/crash counts from current [rubyspec_language.txt](docs/rubyspec_language.txt)

3. Clean [TODO.md](docs/TODO.md):
   - Remove "1.2 Classes in Lambdas - FIXED" from active items
   - Collapse "1.3 super() - MOSTLY FIXED" to note remaining edge case only
   - Update test status counts from current [rubyspec_language.txt](docs/rubyspec_language.txt)
   - Condense "Recently Completed" / "Previously Completed" to brief one-liners

4. Trim [bignums.md](docs/bignums.md) (~1679 lines) to a concise implementation reference
   (~100-200 lines) by removing session logs, debugging traces, and
   step-by-step investigation narratives for completed phases. Keep:
   - Current status summary (all phases complete)
   - Memory layout and representation design
   - API reference (key methods and their purpose)
   - Known limitations and future work
   - Key design decisions (why Array for limbs, sign handling, bootstrap constraints)

**Out of scope:**
- Rewriting ARCHITECTURE.md or DEBUGGING_GUIDE.md
- Updating rubyspec_language.txt itself (done via `make rubyspec-language`)
- Creating new documentation
- Changing any code

## Expected Payoff

- Six fewer files to scan when orienting in the project
- Status data in TODO.md and KNOWN_ISSUES.md matches reality
- [bignums.md](docs/bignums.md) becomes a usable reference instead of a 1679-line session log
- Reduces confusion for AI agents that read docs/ for context
- Total docs/ file count drops from 18 to 12 (33% reduction)

## Proposed Approach

1. Delete the six obsolete files with `git rm`
2. Edit KNOWN_ISSUES.md: remove FIXED items from Active Issues, update counts
3. Edit TODO.md: remove completed items, update test status
4. Rewrite bignums.md: keep summary, layout, API, decisions; drop session logs
5. Commit all changes in a single commit

## Prior Plans

No prior plans exist in docs/plans/ or docs/plans/archived/.

## Acceptance Criteria

- [ ] The six listed files are removed from the working tree (retained in git history)
- [ ] KNOWN_ISSUES.md contains no issues marked FIXED in its Active Issues section
- [ ] KNOWN_ISSUES.md spec counts match the current rubyspec_language.txt summary line
- [ ] TODO.md test status numbers match the current rubyspec_language.txt output
- [ ] TODO.md contains no items marked FIXED as active work items
- [ ] bignums.md is under 250 lines and still documents: current status, all nine phases at summary level, memory layout, key methods, known limitations, and design decisions

## Open Questions

- Should the "Recently Completed" / "Previously Completed" sections in TODO.md be kept at all, or moved to a CHANGELOG? (Propose: keep as a short list, drop detailed descriptions.)

## Implementation Details

### Files to Delete (6 files)

Five of the six files are tracked by git and can be removed with `git rm`:
- [docs/DEVELOPMENT_RULES.md](docs/DEVELOPMENT_RULES.md) (18 lines) — `git rm`
- [docs/RUBYSPEC_INTEGRATION.md](docs/RUBYSPEC_INTEGRATION.md) — `git rm`
- [docs/RUBYSPEC_CRASH_ANALYSIS.md](docs/RUBYSPEC_CRASH_ANALYSIS.md) — `git rm`
- [docs/REJECTED_APPROACH_METHOD_CHAINING.md](docs/REJECTED_APPROACH_METHOD_CHAINING.md) — `git rm`
- [docs/KERNEL_MIGRATION_PLAN.md](docs/KERNEL_MIGRATION_PLAN.md) — `git rm`

One file is **untracked** (appears in `git status` as `??`):
- [docs/INVESTIGATION_POSTFIX_IF_BUG.md](docs/INVESTIGATION_POSTFIX_IF_BUG.md) — plain `rm`

### Cross-Reference Fixup

[docs/control_flow_as_expressions.md](docs/control_flow_as_expressions.md) references the deleted file `REJECTED_APPROACH_METHOD_CHAINING.md` at two locations:
- Line 147: `See REJECTED_APPROACH_METHOD_CHAINING.md for full analysis.`
- Line 181: `- REJECTED_APPROACH_METHOD_CHAINING.md - Why hack was rejected`

Both lines should be updated to note the file was removed (content preserved in git history). Replace with a note like "(removed — retained in git history)" since the lessons are already captured in the same file's "Attempt 3" section.

[docs/bignums.md](docs/bignums.md) references two deleted investigation files at line 506-507:
- `docs/FIXNUM_CLASS_METHOD_INVESTIGATION.md`
- `docs/FIXNUM_TO_INTEGER_MIGRATION.md`

However, these files are NOT in the deletion list and do NOT exist on disk — they are stale references that should simply be removed during the bignums.md rewrite.

### KNOWN_ISSUES.md Edits ([docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md))

**Current state**: 184 lines, last updated 2025-12-01.

**Stale counts at lines 10-13** — replace with current values from [docs/rubyspec_language.txt](docs/rubyspec_language.txt):
- PASSED: 3 → **4** (and_spec, not_spec, unless_spec, *plus one more* — verify from rubyspec_language.txt line 78-80, unless_spec appears twice due to output glitch but the summary says 3; keep as 3 if summary is authoritative)
- FAILED: ~23 → **28**
- CRASHED: ~52 → **47**
- Individual test counts: update to P:272 F:705 S:17 T:994, pass rate 27%

**Active Issues section (lines 42-132)** — remove two FIXED issues:
- **Issue 1** (lines 44-55): "super() Uses Wrong Superclass - FIXED" — delete entire subsection. The remaining edge case (`define_method(:name) { super() }`) should be noted in Issue 2-level detail or kept as a one-liner under "Recent Fixes".
- **Issue 3** (lines 119-131): "Classes in Lambdas - FIXED" — delete entire subsection.

After deletion, renumber remaining active issues:
- Current Issue 2 ("Break from Blocks") → becomes Issue 1
- Current Issue 4 ("Keyword Arguments") → becomes Issue 2
- Current Issue 5 ("Compound Expression After If/Else") → becomes Issue 3

Add one-liner for super() remaining edge case to "Recent Fixes" section or keep as brief note:
- `super()` in `define_method` blocks still unsupported (needs method name from define_method arg).

### TODO.md Edits ([docs/TODO.md](docs/TODO.md))

**Current state**: 117 lines, last updated 2025-12-01.

**Stale counts at lines 9-13** — replace with current values from [docs/rubyspec_language.txt](docs/rubyspec_language.txt):
- PASSED: 3 (4%) → **3 (4%)** (summary line says 3, but individual pass rate is 27% for test cases)
- FAILED: ~23 (29%) → **28 (36%)**
- CRASHED: ~52 (67%) → **47 (60%)**
- Add individual test case stats: 994 total, 272 passed, 705 failed, 17 skipped, 27% pass rate

**Remove section 1.2** (lines 42-44): "Classes in Lambdas - FIXED" — entirely.

**Collapse section 1.3** (lines 48-58): "super() Implementation - MOSTLY FIXED" — reduce to a single bullet noting the remaining `define_method` edge case. Since the main fix is done, this can move to a brief note under the break-from-blocks section or be left as a minimal item.

**Condense "Recently Completed" section** (lines 87-91): Remove detail, keep as brief one-liners.

**Condense "Previously Completed" section** (lines 93-101): Remove detail, keep as brief one-liners.

### bignums.md Rewrite ([docs/bignums.md](docs/bignums.md))

**Current state**: 1678 lines.

**Target**: Under 250 lines. Write a new file preserving these sections from the original:

1. **Status Summary** (~10 lines) — from lines 1-16. All 9 phases complete, selftest-c passes, Fixnum minimized to 10 methods.

2. **Architecture / Design Decisions** (~30 lines) — distilled from:
   - Lines 122-134: "Implementation Approach" (no separate Bignum class, unified Integer)
   - Lines 477-499: "Why Array for Limbs?", "Sign Handling", "Unified Integer Class"
   - Lines 354-382: "No Large Literals During Compilation" constraint (still relevant for bootstrap)

3. **Memory Layout** (~25 lines) — from lines 446-474: Tagged fixnum format, heap-allocated Integer format, detection method, limb representation.

4. **Phase Summary** (~40 lines) — one paragraph per phase distilled from the per-phase sections (lines 135-353, 509-606, 607-1125, 1127-1383, 1384-1467). Keep only: what was implemented, key files, any remaining limitations. No commit hashes, no debugging narratives, no test output.

5. **Key Methods Reference** (~30 lines) — extract from lines 43-77 ("What Works") and the Phase 7 summary (lines 1131-1172). List the important public and internal methods with one-line descriptions.

6. **Known Limitations and Future Work** (~30 lines) — from lines 1625-1678. Keep: compiler-level limitations, arithmetic limitations (broken operators list), future enhancements.

7. **References** (~5 lines) — from lines 501-507, but remove stale file references (FIXNUM_CLASS_METHOD_INVESTIGATION.md, FIXNUM_TO_INTEGER_MIGRATION.md don't exist).

**Content to remove entirely** (the bulk):
- Per-phase "Commits:" lists (dozens of commit hashes)
- "Investigation Notes" and "Bugs Fixed" sub-sections within phases
- "Blocker" narratives in Phase 6 steps (lines 311-329)
- Comprehensive Solution Plan for Phase 7 (lines 626-948) — code examples, Option A/B analysis
- Implementation Roadmap and Progress (lines 948-1125) — session-level detail
- Phase 6 Step 5 detailed implementation (lines 1384-1467)
- Testing Approach section (lines 1468-1534)
- Bignum Comparison Investigation session log (lines 1536-1623)
- All inline test result listings (e.g., lines 91-96, 101-103, 543-551, 599-603, 1176-1183)

## Execution Steps

1. [ ] Delete the five git-tracked obsolete files — run `git rm docs/DEVELOPMENT_RULES.md docs/RUBYSPEC_INTEGRATION.md docs/RUBYSPEC_CRASH_ANALYSIS.md docs/REJECTED_APPROACH_METHOD_CHAINING.md docs/KERNEL_MIGRATION_PLAN.md`
2. [ ] Delete the untracked file — run `rm docs/INVESTIGATION_POSTFIX_IF_BUG.md`
3. [ ] Fix cross-references in [docs/control_flow_as_expressions.md](docs/control_flow_as_expressions.md) — update lines 147 and 181 to replace references to `REJECTED_APPROACH_METHOD_CHAINING.md` with a note that the file was removed (content preserved in git history, lessons already captured in Attempt 3 section above)
4. [ ] Edit [docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md) — update the "Current State Summary" counts (lines 10-13) to match [docs/rubyspec_language.txt](docs/rubyspec_language.txt): Passed 3, Failed 28, Crashed 47; individual tests: 994 total, 272 passed, 705 failed, 17 skipped, 27% pass rate
5. [ ] Edit [docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md) — remove FIXED Issue 1 (lines 44-55, "super() Uses Wrong Superclass") and FIXED Issue 3 (lines 119-131, "Classes in Lambdas") from Active Issues; renumber remaining issues; add super() remaining edge case (`define_method` blocks) as a brief note under Recent Fixes
6. [ ] Edit [docs/TODO.md](docs/TODO.md) — update the "Test Status" counts (lines 9-13) to match [docs/rubyspec_language.txt](docs/rubyspec_language.txt): Passed 3 (4%), Failed 28 (36%), Crashed 47 (60%); add individual test case stats (994 total, 272 passed, 27% pass rate)
7. [ ] Edit [docs/TODO.md](docs/TODO.md) — remove section 1.2 "Classes in Lambdas - FIXED" (lines 42-44); collapse section 1.3 "super() Implementation" (lines 48-58) to a single bullet for the remaining `define_method` edge case
8. [ ] Edit [docs/TODO.md](docs/TODO.md) — condense "Recently Completed" (lines 87-91) and "Previously Completed" (lines 93-101) sections to brief one-liner lists without detailed descriptions
9. [ ] Rewrite [docs/bignums.md](docs/bignums.md) — replace the 1678-line file with a concise implementation reference under 250 lines, preserving: status summary, architecture/design decisions, memory layout, one-paragraph-per-phase summary, key methods reference, known limitations, and references. Remove all commit hashes, debugging session logs, investigation narratives, blocker analyses, and inline test output
10. [ ] Verify acceptance criteria — confirm: six files removed, no FIXED items in KNOWN_ISSUES.md Active Issues, spec counts match rubyspec_language.txt in both KNOWN_ISSUES.md and TODO.md, bignums.md is under 250 lines with all required content sections present

---
*Status: APPROVED (implicit via --exec)*