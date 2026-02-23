SPECSYM
Created: 2026-02-23 04:01

# Add Rubyspec Core Type Targets: nil, true, false, symbol

[COMPLANG] Add Makefile targets for rubyspec/core/nil/, core/true/, core/false/, and core/symbol/ — four small suites with complete or near-complete implementations in lib/core/ that will show broader compliance beyond language/ alone.

## Goal Reference

[COMPLANG](docs/goals/COMPLANG-compiler-advancement.md): Adding these targets directly enables tracking compliance for four implemented core types, expanding the suite coverage from 3 tracked suites (language, integer, regexp) to 7.

Also advances [SELFHOST](docs/goals/SELFHOST-clean-bootstrap.md): Running these specs validates that the core library implementations (nil.rb, true.rb, false.rb, symbol.rb) work correctly in the self-hosted context.

## Prior Plans

- No prior plans target Makefile rubyspec target expansion.
- The [rubyspec-compliance-landscape.md](docs/exploration/rubyspec-compliance-landscape.md) exploration note explicitly suggests: "Add Makefile targets for core/nil, core/true, core/false, core/symbol suites" as a quick-win opportunity.

## Root Cause

The Makefile currently only tracks three rubyspec suites:
- `rubyspec-language` (80 files, 27% pass rate)
- `rubyspec-integer` (67 files, results truncated)
- `rubyspec-regexp` (24 files, 42% pass rate)

The compiler has complete or near-complete implementations of several core types in lib/core/:
- [lib/core/nil.rb](lib/core/nil.rb) — 61 lines, ~13 methods, marked "Complete" in exploration
- [lib/core/true.rb](lib/core/true.rb) — 48 lines, 8 methods, marked "Complete"
- [lib/core/false.rb](lib/core/false.rb) — 48 lines, 8 methods, marked "Complete"
- [lib/core/symbol.rb](lib/core/symbol.rb) — 135 lines, 13 methods, "Implemented"

These implementations exist but have no rubyspec tracking. The exploration notes identify this as a gap: "Quick-win suite expansion: run core/nil, core/true, core/false to show broader compliance." Running these small suites (18 + 9 + 9 + 31 = 67 spec files) would reveal:
1. The actual compliance rate for these complete/near-complete types
2. Specific method gaps that cause failures (if any)
3. Whether the compiler handles more of rubyspec than language/ alone suggests

## Infrastructure Cost

Zero. This adds four simple Makefile targets that invoke the existing `./run_rubyspec` script with new arguments. No new files, no build system changes, no tooling changes. The run_rubyspec infrastructure is proven by the existing targets.

## Scope

**In scope:**

1. Add four new Makefile targets:
   - `rubyspec-nil`: runs `./run_rubyspec rubyspec/core/nil/` → `docs/rubyspec_nil.txt`
   - `rubyspec-true`: runs `./run_rubyspec rubyspec/core/true/` → `docs/rubyspec_true.txt`
   - `rubyspec-false`: runs `./run_rubyspec rubyspec/core/false/` → `docs/rubyspec_false.txt`
   - `rubyspec-symbol`: runs `./run_rubyspec rubyspec/core/symbol/` → `docs/rubyspec_symbol.txt`

2. Run each target to capture baseline compliance data

3. Document results in a summary section of the compliance tracking (e.g., update coverage.md or create a new compliance summary)

**Out of scope:**
- Fixing any failures discovered (that would be follow-up plans)
- Adding more rubyspec targets (array, hash, string, kernel, etc.) — those are larger suites requiring more analysis
- Modifying run_rubyspec or rubyspec_helper.rb
- Running the full rubyspec suite

## Expected Payoff

**Immediate:**
- Track compliance for 4 new core types (67 spec files total)
- Reveal actual pass rates for complete/near-complete implementations (nil, true, false, symbol)
- Provide baseline data for future improvement tracking
- Demonstrate that the compiler handles more of rubyspec than language/ alone (the current 27% metric undersells progress)

**Downstream (COMPLANG):**
- Each failing spec file identifies a specific method gap to fix
- High pass rates would validate the core library implementations
- Low pass rates would identify specific methods needing implementation
- Enables COMPLANG to track 7 suites instead of 3

**Documentation:**
- Updates the "Tracked Suites" table in [rubyspec-compliance-landscape.md](docs/exploration/rubyspec-compliance-landscape.md) with actual pass rates for nil, true, false, symbol

## Proposed Approach

1. **Add Makefile targets**: Append four targets following the existing pattern:
   ```make
   .PHONY: rubyspec-nil
   rubyspec-nil:
   	./run_rubyspec rubyspec/core/nil/ 2>&1 | tee docs/rubyspec_nil.txt
   
   .PHONY: rubyspec-true
   rubyspec-true:
   	./run_rubyspec rubyspec/core/true/ 2>&1 | tee docs/rubyspec_true.txt
   
   .PHONY: rubyspec-false
   rubyspec-false:
   	./run_rubyspec rubyspec/core/false/ 2>&1 | tee docs/rubyspec_false.txt
   
   .PHONY: rubyspec-symbol
   rubyspec-symbol:
   	./run_rubyspec rubyspec/core/symbol/ 2>&1 | tee docs/rubyspec_symbol.txt
   ```

2. **Run each target**: Execute `make rubyspec-nil`, `make rubyspec-true`, `make rubyspec-false`, `make rubyspec-symbol` to capture baseline results.

3. **Analyze results**: Parse the output files to extract:
   - File-level pass/fail/crash counts
   - Individual test pass rates
   - Any common failure patterns

4. **Document results**: Update the exploration notes or create a summary with the new compliance data.

## Acceptance Criteria

- [ ] [Makefile](Makefile) contains `rubyspec-nil` target that runs `./run_rubyspec rubyspec/core/nil/` and outputs to `docs/rubyspec_nil.txt`
- [ ] [Makefile](Makefile) contains `rubyspec-true` target that runs `./run_rubyspec rubyspec/core/true/` and outputs to `docs/rubyspec_true.txt`
- [ ] [Makefile](Makefile) contains `rubyspec-false` target that runs `./run_rubyspec rubyspec/core/false/` and outputs to `docs/rubyspec_false.txt`
- [ ] [Makefile](Makefile) contains `rubyspec-symbol` target that runs `./run_rubyspec rubyspec/core/symbol/` and outputs to `docs/rubyspec_symbol.txt`
- [ ] `make rubyspec-nil` executes successfully and produces `docs/rubyspec_nil.txt`
- [ ] `make rubyspec-true` executes successfully and produces `docs/rubyspec_true.txt`
- [ ] `make rubyspec-false` executes successfully and produces `docs/rubyspec_false.txt`
- [ ] `make rubyspec-symbol` executes successfully and produces `docs/rubyspec_symbol.txt`
- [ ] Each results file contains pass/fail/crash summary data
- [ ] Compliance data is documented (updated exploration notes or new summary)

## Open Questions

- Will all four suites run without hitting the 30-second timeout? The existing targets use a 30s timeout per spec file. These are small suites (9-18 files each), so they should complete quickly even if individual files timeout.
- Are there any sed workarounds needed for these specific suites? The existing language/regexp/integer targets work with the current run_rubyspec. These core type suites may have different patterns but likely work with existing workarounds.
- What pass rate is expected? Based on exploration notes, nil/true/false are marked "Complete" so expect high pass rates. Symbol has 13 methods implemented; the 31 spec files may reveal gaps.

---
*Status: PROPOSAL - Awaiting approval*