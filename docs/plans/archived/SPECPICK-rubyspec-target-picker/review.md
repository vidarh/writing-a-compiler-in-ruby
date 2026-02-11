<!-- content_hash: 375cc41290cdbb68817ed95b3f650d1e:e941ee86203a11ff06d45f2cc13f65fe -->
<!-- reviewed: 2026-02-10 23:58 -->

### SPECPICK — Rubyspec Target Picker Script
- **Location**: archived
- **Status**: REJECTED — The focus on rubyspec_language.txt is flawed. Rubyspec_language.txt only tallies a very tiny subset of rubyspec. The plan needs an approach to running a broader, and broadening set of suites - e.g. maybe overnight, re-running a smaller subset (e.g the category being worked on) to prevent regressions - and picking from them. It is not necessary to rank the spec files. Just pick a spec file at random, run an explore step on that spec if one hasn't been done, and then create a plan for attempting to fix it. It's likely the runner, running --exec, should have a max time limit, and that the given plan should be deferred if it can't be addressed in that time (for manual restart). This plan aims far too small.
- **Lines**: 69
- **Created**: 2026-02-10 21:45
- **Sections present**: Goal Reference, Root Cause, Infrastructure Cost, Scope, Expected Payoff, Proposed Approach, Prior Plans, Acceptance Criteria, Open Questions
- **Has Root Cause section**: yes
- **Has Prior Plans section**: yes (only references DOCCLN as unrelated)
- **Has Infrastructure Details**: yes (Infrastructure Cost section: "Minimal")
- **Has Execution Steps**: no (has Proposed Approach with 5 numbered sub-items)
- **Acceptance criteria**: 4 total, 0 checked, 4 unchecked
- **FAIL notes on criteria**: none
- **Feedback/revision sections**: 0
- **Execution log entries**: 1 (immediate rejection)
- **Spec snapshots**: 0
- **Document coherence**: Internally consistent and well-structured
- **Key issues**: Plan proposed a ranking script (`tools/pick_rubyspec_target.rb`) that only worked on the existing 78-file language suite. Rejection feedback was extensive and specific: (1) coverage too narrow, (2) ranking unnecessary (random selection better), (3) missing explore-fix-defer loop, (4) needs time limiting, (5) needs broader suite infrastructure. The rejection essentially provided a complete counter-specification.
- **Assessment**: This plan aimed too small in both scope and ambition. It proposed a tactical utility (ranking script) when the strategic need was comprehensive automation (broader coverage + autonomous loop). The detailed rejection feedback shows the user had a clear vision of what was needed; this plan represented incremental thinking when transformative change was required. Well-written but fundamentally misaligned with project needs.
