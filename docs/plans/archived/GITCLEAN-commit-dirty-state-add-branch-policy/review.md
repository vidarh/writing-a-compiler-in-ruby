<!-- content_hash: 7246f7268a77e6d5ce063134c7e11d34:265b207c9ae6cb3a571a3bfb1651c74e -->
<!-- reviewed: 2026-02-11 11:23 -->

### GITCLEAN — Commit Dirty Working Tree, Clean Rubyspec Submodule, and Establish Branch Policy
- **Location**: active
- **Status**: PROPOSAL - Awaiting approval
- **Lines**: 106
- **Created**: 2026-02-11
- **Sections present**: Root Cause, Infrastructure Cost, Scope, Expected Payoff, Proposed Approach, Acceptance Criteria
- **Has Root Cause section**: yes
- **Has Prior Plans section**: no
- **Has Infrastructure Details**: yes (Infrastructure Cost section)
- **Has Execution Steps**: no (only Proposed Approach with phases)
- **Acceptance criteria**: 8 total, 0 checked, 8 unchecked
- **FAIL notes on criteria**: none (all criteria are well-specified and testable)
- **Feedback/revision sections**: 0
- **Execution log entries**: 1 (revision requested 2026-02-11 10:58)
- **Spec snapshots**: 1 (spec.2026-02-11-1058-pre-revise.md)
- **Document coherence**: Internally consistent. The plan correctly prioritizes submodule cleanup (Phase 1) before commits (Phase 2), and appropriately recognizes that changes are already on master so cannot be branched retroactively. The new policies (Phase 3) prevent recurrence.
- **Key issues**: The log shows a revision was requested regarding rubyspec submodule hygiene and the aspiration to pass unmodified specs, but the current spec already fully addresses this in lines 12-14 and scope item 4 (lines 44-49). The revision appears to have been successfully incorporated. The plan awaits approval with no apparent blocking issues.
- **Assessment**: This is a thorough cleanup plan with clear phases, well-justified scope boundaries, and strong root cause analysis. The submodule pollution is correctly identified as a violation of core project principles. The acceptance criteria are comprehensive and verifiable. The plan appropriately handles the bootstrapping problem (can't branch from already-dirty master) and establishes policies to prevent recurrence. Ready for approval and execution.
