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

---
*Status: APPROVED (implicit via --exec)*