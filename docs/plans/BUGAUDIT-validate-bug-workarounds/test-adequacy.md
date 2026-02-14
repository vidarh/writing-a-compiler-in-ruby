# BUGAUDIT Test Adequacy Assessment

Reviewer: test-adequacy reviewer (2026-02-14)

## Test Suite Run Results

### Commands Run

```bash
make spec
```
This runs `./run_rubyspec ./spec` which processes all `*_spec.rb` files.

### Exit Code
Non-zero (all compilation failures).

### Exact Output
```
Summary:
  Total spec files: 98
  Passed: 0
  Failed: 0
  Crashed (no test output): 0
  Failed to compile: 98

Individual Test Cases:
  Total tests: 0
  Passed: 0
  Failed: 0
  Skipped: 0
```

All 98 specs failed to compile. Root cause: `docker: Cannot connect to the Docker daemon at unix:///var/run/docker.sock`. The sandbox environment does not expose the Docker socket, so the compiler's assembler/linker stage (which runs inside Docker) cannot execute.

**This is an environment limitation, not a test defect.** The Docker daemon is running on the host (`systemctl status docker` shows active), but the socket file (`/var/run/docker.sock`) does not exist in the sandbox. The `make selftest-mri` target (which doesn't require Docker) passes with 0 failures, confirming Ruby and the compiler frontend work.

### Additional verification: `make selftest-mri`
```bash
make selftest-mri
```
Result: `DONE` / `Fails: 0` — confirms the compiler's self-test passes under MRI.

### Execution Agent's Recorded Results

Per `exec-2026-02-14-0306.log`, the execution agent ran all specs with Docker available and recorded:

| Spec File | Result |
|-----------|--------|
| `bug_yield_in_nested_block_spec.rb` | All 5 tests crash at runtime (CONFIRMED) |
| `bug_variable_name_collision_spec.rb` | 3 pass, 2 fail + 2 confirmed via crash/compile-fail in comments |
| `bug_ternary_expression_spec.rb` | 6 pass, 1 fail (CONFIRMED `||` ternary) |
| `bug_block_given_nested_spec.rb` | 1 pass, 1 fail + 3 confirmed crash in comments |
| `bug_self_recursive_lambda_spec.rb` | 5/5 pass (STALE) |
| `bug_parser_divergence_spec.rb` | 5/5 pass (construct works) |
| `bug_break_in_block_spec.rb` | 3 pass, 1 fail + nested break segfault in comments |

---

## Scenario Coverage Analysis

### Category 1: spec/bug_yield_in_nested_block_spec.rb

| # | Required Scenario (test.md) | Present? | Location |
|---|----------------------------|----------|----------|
| 1 | yield inside a nested do-block | YES | `with_thing` lines 14-18, test lines 61-67 |
| 2 | yield with multiple arguments from nested block | YES | `multi_yield` lines 26-31, test lines 69-76 |
| 3 | yield from method with &block, inside with_register-style pattern | YES | `with_conditional` lines 33-43, test lines 78-90 |
| 4 | yield from doubly-nested block | YES | `doubly_nested` lines 45-51, test lines 92-98 |
| 5 | yield with no arguments from nested block | YES | `yield_no_args` lines 53-57, test lines 100-106 |

**Verdict: COMPLETE** (5/5 scenarios)

### Category 2: spec/bug_variable_name_collision_spec.rb

| # | Required Scenario (test.md) | Present? | Location / Notes |
|---|----------------------------|----------|-----------------|
| 1 | Local var shadows method name inside block | YES | `VarCollisionRest` lines 16-29 |
| 2 | Local var shadows method name inside lambda | YES | `VarCollisionReg` lines 31-45 |
| 3 | String interpolation with outer-scope variable inside block | YES | `VarCollisionInterp` lines 47-56 |
| 4 | Argument named `range` triggering constructor rewrite | **NO** | Not present — no `it` block, no commented-out test. Only a header comment (line 12) mentions it. |
| 5 | Variable not initialized to nil without explicit assignment | PARTIAL | Workaround `with_nil` tested (lines 76-80, 105-108). Bug-reproducing `without_nil` commented out with CONFIRMED annotation (lines 82-89). Acceptable for crash-causing bug. |
| 6 | Variable named same as method in nested do blocks | YES | `VarCollisionDividend` lines 58-73 |
| 7 | Method name collision across multiple nesting levels | **NO** | Not present. test.md requests lambda-in-lambda with naming collision. |

**Verdict: GAP** — 5 of 7 scenarios present. Missing `range` argument test (#4) and deep nesting collision (#7).

### Category 3: spec/bug_ternary_expression_spec.rb

| # | Required Scenario (test.md) | Present? | Location |
|---|----------------------------|----------|----------|
| 1 | Ternary with `\|\|`, first truthy | YES | Lines 12-17 |
| 2 | Ternary with `\|\|`, first falsy, second truthy | YES | Lines 19-24 |
| 3 | Ternary with `\|\|`, both falsy | YES | Lines 26-29 |
| 4 | Ternary assigned to variable, used in method call | YES | Lines 31-36 |
| 5 | Ternary assigned to variable, lv is nil (else branch) | YES | Lines 38-43 |
| 6 | Ternary with array wrapping condition | YES | Lines 45-49 |
| 7 | Nested ternary | YES | Lines 51-57 |

**Verdict: COMPLETE** (7/7 scenarios)

### Category 4: spec/bug_block_given_nested_spec.rb

| # | Required Scenario (test.md) | Present? | Location / Notes |
|---|----------------------------|----------|-----------------|
| 1 | block_given? nested do-block (block passed) | COMMENTED | Lines 12-18, 52-56. CONFIRMED segfault. |
| 2 | block_given? nested do-block (no block passed) | **NO** | Not present. However, since the method itself segfaults (scenario 1), calling it without a block would also crash. Untestable. |
| 3 | block_given? captured to local (workaround) | YES | Lines 20-27, 63-68. Tests both with-block and without-block. |
| 4 | block_given? doubly-nested block | COMMENTED | Lines 33-42, 70-74. CONFIRMED segfault. |
| 5 | block_given? inside lambda inside method | COMMENTED | Lines 44-48, 76-80. CONFIRMED segfault. |

Bonus: includes top-level `block_given?` baseline test (lines 58-62).

**Verdict: MINOR GAP** — 4 of 5 scenarios addressed. Missing #2 is untestable (method segfaults regardless of block presence).

### Category 5: spec/bug_self_recursive_lambda_spec.rb

| # | Required Scenario (test.md) | Present? | Location |
|---|----------------------------|----------|----------|
| 1 | Self-recursive lambda | YES | Lines 27-38. Uses if/else (avoids ternary per pitfall #12). |
| 2 | Lambda iterating and calling method on self | YES | `LambdaIter` class, lines 12-24, test at 40-42 |
| 3 | Lambda called multiple times | YES | Lines 44-49 |
| 4 | Inline form: items.each calling self.method | YES | Lines 51-58 |
| 5 | Mutually recursive lambdas | YES | Lines 60-81 |

**Verdict: COMPLETE** (5/5 scenarios)

### Category 6: spec/bug_parser_divergence_spec.rb

| # | Required Scenario (test.md) | Present? | Location |
|---|----------------------------|----------|----------|
| 1 | Method call with arithmetic argument | YES | Lines 26-29 |
| 2 | Same, inside block | YES | Lines 31-37 |
| 3 | Method call with subtraction | YES | Lines 39-42 |
| 4 | Chained method call with arithmetic | YES | Lines 44-48 |
| 5 | Conditional array concat based on type | YES | Lines 50-58 |

**Verdict: COMPLETE** (5/5 scenarios)

### Category 7: spec/bug_break_in_block_spec.rb

| # | Required Scenario (test.md) | Present? | Location / Notes |
|---|----------------------------|----------|-----------------|
| 1 | break inside each, value used after | YES | Lines 12-20 |
| 2 | break with multiple local variables (4-5+) | YES | Lines 41-56. Uses 5 locals (a, b, c, d, found). |
| 3 | break with value (return value of iteration) | **NO** | Not present. test.md specifies `break value` form. Distinct language feature. |
| 4 | break inside nested iteration | COMMENTED | Lines 58-69. CONFIRMED segfault. |
| 5 | break with method calls before break point | YES | Lines 31-39 |
| 6 | break as first statement in block | YES | Lines 22-29 |

**Verdict: GAP** — 5 of 6 scenarios addressed. Missing `break value` form (#3).

---

## Cross-Cutting Assessment

### 1. Do test files exist for the changes made?

**YES.** All 7 spec files exist covering all 7 bug categories. The two code changes (workaround removals in `compile_arithmetic.rb` and `compile_class.rb`) are covered by Category 2 and Category 5 specs respectively, and were additionally validated by `make selftest && make selftest-c` during execution.

### 2. Are external dependencies properly mocked/stubbed?

**N/A — no external dependencies.** These specs test Ruby language constructs. No mocking needed. No network access, no live services, no credentials. The only dependency is the project's own `rubyspec_helper.rb` which is bundled by the compiler. Correct per test.md design.

### 3. Do the tests cover error paths, not just happy paths?

**PARTIALLY.** For confirmed bugs, the "error path" is the bug-triggering construct itself. Several bugs cause segfaults or compilation failures, which cannot be tested as runnable assertions. The execution agent documented these as commented-out code with `CONFIRMED` annotations. This is the correct approach for this project — you cannot assert on a segfault in mspec.

For STALE categories (Cat 5, Cat 6), the passing tests serve as regression tests. If the constructs broke again, the tests would fail.

### 4. Would the tests FAIL if the implementation were reverted or broken?

**YES, for the relevant categories:**

- **Cat 1 (yield):** Currently crash. Would detect fix (tests pass) and detect regression (tests crash again).
- **Cat 2 (variable collision):** Active tests assert correct values (`"local_rest"` not `"method_rest"`). Would catch regressions.
- **Cat 3 (ternary):** The `||` ternary test asserts `"yes"` but bug returns `true`. Would catch fix and regression.
- **Cat 4 (block_given?):** Workaround test verifies the capture pattern works. Would catch if `block_given?` broke entirely.
- **Cat 5 (lambda):** All pass. Recursive lambda returning 120, mutual recursion checks — would catch regressions.
- **Cat 6 (parser):** All pass. `arr.size + 1` must equal 4 — would catch parser regressions.
- **Cat 7 (break):** Multi-variable test checks all locals retain values post-break. Would detect register corruption.

### 5. Do the tests exercise the specific code paths that were added/modified?

**YES for workaround removals:**
- `xdividend → dividend` (compile_arithmetic.rb): `VarCollisionDividend` in Cat 2 spec tests this exact pattern (variable with same name as method in nested blocks).
- `compile_ary_do` inlining (compile_class.rb): `LambdaIter.run` in Cat 5 spec tests `each`-with-method-call inlined form.

Both were further validated by `make selftest && make selftest-c`, the definitive compiler validation.

### 6. Are there scenarios in test.md that have no corresponding test?

**YES.** 4 scenarios are missing:

| Category | Scenario | Description | Impact |
|----------|----------|-------------|--------|
| Cat 2 | #4 | Argument named `range` triggering constructor rewrite | **MEDIUM** — confirmed compilation-failure bug with no test at all |
| Cat 2 | #7 | Deep nesting collision (lambda-in-lambda) | **LOW** — edge case of tested patterns |
| Cat 4 | #2 | block_given? nested, no-block variant | **LOW** — untestable; method segfaults regardless |
| Cat 7 | #3 | `break value` form | **MEDIUM** — distinct feature, may reveal different failure |

### 7. Is the code properly abstracted to support mocking?

**N/A.** These are language-level construct tests. The compiler is the implicit SUT (it compiles and runs the spec). No mocking needed, and the test.md explicitly confirms this. The approach is architecturally sound.

---

## Overall Verdict: **ADEQUATE**

### Summary

- **Total required scenarios across all categories:** 40
- **Present (runnable or documented as commented-out CONFIRMED):** 36 (90%)
- **Missing:** 4 (10%)
- **All 7 required spec files:** Created, correctly formatted (mspec with `require_relative`)
- **All 7 bug categories:** Covered by at least one spec file
- **Workaround removals:** 2 removed, validated by selftest + selftest-c (per execution log)
- **Test suite execution:** Could not run in current environment (Docker socket unavailable). Execution agent's recorded results are the authoritative source.

### Rationale for ADEQUATE

The plan's acceptance criteria require "at least one mspec test per distinct root-cause category" — all 7 categories have tests. The 4 missing scenarios are:

1. **`range` argument collision** — The most notable gap. A commented-out test documenting the compilation failure would be valuable. However, the bug is already CONFIRMED in the execution log and summary table with "Compilation failure" as evidence.

2. **Deep nesting collision** — Edge case extension of 6 tested collision patterns. Low risk of missing a distinct failure mode.

3. **No-block variant of block_given? nested** — Cannot be tested; the method segfaults before block_given? is evaluated.

4. **`break value` form** — Potentially distinct from plain `break`. However, the 4 existing break tests plus the nested-break segfault documentation cover the register-corruption aspect identified in the @bug marker.

### Execution agent's adherence to test.md guidelines

The agent correctly:
- Used mspec format throughout
- Avoided ternaries in recursive lambda test (pitfall #12)
- Avoided instance variables in specs (pitfall #5 about `run_rubyspec` rewriting `@var`)
- Skipped the out-of-scope `rescue` marker (pitfall #6)
- Documented confirmed-crash bugs as commented-out code rather than deleting them
- Tested workaround removals one at a time per safety guidelines

### Recommended Improvements (not blockers)

1. Add a commented-out `range` argument test to `bug_variable_name_collision_spec.rb` documenting the compilation failure
2. Add a `break value` test (`result = [1,2,3].detect { |x| break x * 10 if x == 2 }`) to `bug_break_in_block_spec.rb`
3. Add the deep-nesting lambda collision test as an edge case to `bug_variable_name_collision_spec.rb`
