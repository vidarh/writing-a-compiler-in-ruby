<!-- content_hash: ea266a3bdf7d9528ebfce55647426559:nolog -->
<!-- reviewed: 2026-02-11 11:23 -->

### BOOLOPS — Add Missing Boolean Logical Operators (&, |, ^)
- **Location**: active
- **Status**: PROPOSAL - Awaiting approval
- **Lines**: 73
- **Created**: 2026-02-11
- **Sections present**: Goal Reference, Root Cause, Infrastructure Cost, Scope, Expected Payoff, Proposed Approach, Acceptance Criteria, Open Questions
- **Has Root Cause section**: yes
- **Has Prior Plans section**: no
- **Has Infrastructure Details**: yes (Infrastructure Cost section)
- **Has Execution Steps**: no (only Proposed Approach with numbered steps)
- **Acceptance criteria**: 4 total, 0 checked, 4 unchecked
- **FAIL notes on criteria**: none (all criteria are executable tests)
- **Feedback/revision sections**: 0
- **Execution log entries**: 0 (no log.md file)
- **Spec snapshots**: 0
- **Document coherence**: Internally consistent. The root cause analysis correctly traces the missing methods and segfaults to incomplete `__true?` implementations. The scope boundaries are clear and appropriate. The proposed approach is straightforward.
- **Key issues**: The Open Questions section raises a valid implementation detail about whether `Object#__true?` should return Ruby `true` or low-level `%s(sexp 1)`. This should be resolved before execution by examining how the existing FalseClass/NilClass implementations use these values. Otherwise the plan is solid.
- **Assessment**: This is a well-specified fix plan with concrete root cause analysis backed by live spec execution. The problem (missing boolean operators on NilClass, missing `__true?` helper on TrueClass/Object) is clearly identified and the solution is minimal. The payoff metrics are specific (file-level pass rate improvements, reduction from segfault to PASS). The open question should be investigated before approval, but the plan is otherwise ready for execution.
