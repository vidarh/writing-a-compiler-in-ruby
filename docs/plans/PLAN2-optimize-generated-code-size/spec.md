PLAN2
Created: 2026-02-19 04:00
# Optimize Generated Code Size

## Scope
This plan aims to initiate the CODEGEN goal by introducing foundational infrastructure for code size optimization. The primary deliverable is a new test suite that verifies the generated code size for critical core operations (e.g., method calls, simple arithmetic) and enforces a maximum size limit. This will establish a baseline and prevent future regressions.

## Expected Payoff
1. **Prevent Code Bloat:** Automatically catch any changes that cause the generated machine code to become excessively large.
2. **Enable Future Optimizations:** Create the necessary harness for implementing specific optimization passes (e.g., constant folding, dead code elimination) in the future.
3. **Improve Compiler Performance:** Smaller code is often faster to execute and takes less memory.
4. **Increase Confidence:** Provide a quantitative metric for code generation quality.

## Root Cause
The root cause of poor output code quality is the complete absence of any system to measure, enforce, or improve it. The compiler generates code without any feedback loop regarding the efficiency of its output. Key evidence includes:

- A search for `CodeBuilder` or patterns like `emit`, `gen`, `codegen` in the `lib/` directory only returns core library `.rb` files, suggesting the code generation logic might be poorly structured or located in an unexpected place.
- The core [lib/core/integer.rb](lib/core/integer.rb) file is 4398 lines long, indicating highly complex logic for fundamental operations. Without optimization, this complexity likely translates directly into verbose and inefficient machine code.
- There are zero tests (`spec/` directory) that assert anything about the size or quality of the generated code. The lack of test coverage for this critical aspect means any degradation goes unnoticed.
- No prior exploration notes or plans mention code generation quality, signifying a long-standing, unaddressed gap in the compiler's development.

This represents a fundamental missing piece in the compiler's architecture, not just a bug to be fixed.

## Infrastructure Cost
The infrastructure cost is low to moderate. This plan requires integrating with the existing compiler binary and test framework. The changes are self-contained within a new test file and do not require pulling in external large projects. The scope of introducing a testing harness is appropriate for this level of integration, as it provides immediate value (regression protection) and lays groundwork for future, more complex optimizations.

## Prior Plans
No prior plans were found that target the `CODEGEN` goal or the general area of output code quality, optimization, or generated size. A search of the `docs/plans/archived/` directory for related keywords returned no results. This plan initiates a completely new area of work.

## Acceptance Criteria
- A new file `spec/compiler/code_size_spec.rb` is created.
- The file contains at least 3 test cases that compile simple Ruby expressions (e.g., `def test; 1 + 1; end`, a simple method call, a variable assignment).
- Each test case uses a new `code_size` matcher (or equivalent mechanism) to assert that the generated assembly or bytecode for the compiled function is below a predefined threshold (e.g., `expect(compiled_function).to have_code_size < 50`).
- The test suite fails if any of these size limits are exceeded.
- The plan document [links to the new spec file](spec/compiler/code_size_spec.rb) and all referenced core library files.

---
*Status: PROPOSAL*
