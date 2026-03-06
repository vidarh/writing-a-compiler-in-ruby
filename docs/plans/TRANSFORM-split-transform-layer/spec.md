TRANSFORM
Created: 2026-03-06

# Split Transform Layer into Cohesive Modules

[PARSARCH] Split [transform.rb](../../transform.rb) (1,748 lines, 34 methods) into focused modules following the `compile_*.rb` pattern — extracting variable rewriting, constant rewriting, control flow transforms, and pattern matching into separate files for improved maintainability and clearer dependencies.

## Goal Reference

[PARSARCH](../../goals/PARSARCH-parser-architecture.md): Improving the internal architecture and modularity of the compiler's AST transformation layer.

Also advances [SELFHOST](../../goals/SELFHOST-clean-bootstrap.md): The file header in transform.rb states *"Ideally these will be broken out of the Compiler class at some point"* — this plan completes that refactoring.

## Root Cause

The [transform.rb](../../transform.rb) file has grown to **1,748 lines** containing **34 methods** that handle diverse AST transformation concerns:

- **Variable analysis/rewriting** (lines 566-823): `find_vars`, `find_vars_ary`, `rewrite_env_vars`, `rewrite_let_env`, `in_scopes`, `is_special_name?`, `push_var`
- **Constant rewriting** (lines 446-565): `rewrite_strconst`, `symbol_name`, `rewrite_integer_constant`, `rewrite_symbol_constant`, `rewrite_operators`
- **Control flow transforms** (lines 989-1415): `rewrite_range`, `create_concat`, `rewrite_concat`, `build_class_scopes`, `build_class_scopes_for_class`, `flatten_comma`, `rewrite_destruct`, `rewrite_yield`, `rewrite_for`, `setup_global_scope`, `register_constants`, `flatten_deref`, `preprocess`
- **Pattern matching** (lines 23-218): `rewrite_pattern_matching`
- **Lambda/proc transforms** (lines 219-404): `rewrite_proc_return`, `rewrite_lambda`, `convert_ternalt_in_calls`, `group_keyword_arguments`
- **Argument transforms** (lines 1508-1748): `rewrite_forward_args`, `rewrite_keyword_args`, `rewrite_default_args`

These concerns are distinct but intermixed in a single file, making it difficult to:
1. Locate specific transformation logic
2. Understand dependencies between transform phases
3. Safely modify one transform without affecting others
4. Enable parallel work on different transform areas

The file header explicitly acknowledges this: *"Ideally these will be broken out of the Compiler class at some point / For now they're moved here to start refactoring."* The `compile_*.rb` files ([compile_calls.rb](../../compile_calls.rb), [compile_control.rb](../../compile_control.rb), [compile_class.rb](../../compile_class.rb), etc.) demonstrate a proven pattern for splitting the Compiler class by concern.

## Prior Plans

- **[YIELDFIX](../YIELDFIX-fix-yield-in-nested-blocks/spec.md)** (Status: PROPOSAL): Targets a specific bug in `rewrite_yield` within transform.rb. This cleanup plan doesn't conflict — YIELDFIX can be applied before or after the split; if after, the fix applies to `transform_control.rb`.
- **[BGFIX](../BGFIX-fix-block-given-in-nested-blocks/spec.md)** (Status: PROPOSAL): Adds `block_given?` expansion to `rewrite_env_vars`. Same relationship as YIELDFIX — can apply before or after.
- **[ENVFIX](../ENVFIX-fix-callm-method-name-rewrite/spec.md)** (Status: PROPOSAL): Fixes a bug in `rewrite_env_vars`. Same relationship.
- **No prior cleanup plans for transform.rb** — the file has been gradually accumulating methods since it was first extracted from compiler.rb, but no systematic refactoring has been attempted.

## Infrastructure Cost

**Low to Medium**. This plan creates 5 new source files and modifies the require structure in [compiler.rb](../../compiler.rb). No changes to:
- Build system (Makefile)
- Test infrastructure (run_rubyspec)
- Runtime (lib/core/)
- Docker environment

The existing `make selftest` and `make selftest-c` validation is sufficient to verify correctness — the transforms must produce identical AST output before and after the split.

## Scope

**In scope:**

1. **Create 5 new transform module files** following the `compile_*.rb` naming convention:
   - `transform_variables.rb`: Variable analysis and environment rewriting (lines 566-823)
   - `transform_constants.rb`: String/integer/symbol/operator constant rewriting (lines 446-565)
   - `transform_control.rb`: Control flow, scoping, yield/for/range transforms (lines 989-1415)
   - `transform_patterns.rb`: Pattern matching rewrite (lines 23-218)
   - `transform_procs.rb`: Lambda/proc/argument transforms (lines 219-404, 1508-1748)

2. **Update [compiler.rb](../../compiler.rb)**: Replace `require 'transform'` with requires for the 5 new modules

3. **Update [transform.rb](../../transform.rb)**: Convert to a "meta-loader" that requires the 5 sub-modules (for backward compatibility during transition), or remove entirely

4. **Preserve all method signatures and behavior**: No functional changes — this is a pure code movement refactor

5. **Validate**: `make selftest`, `make selftest-c`, `make spec` must all pass with zero regressions

**Out of scope:**

- Bug fixes in any transform methods (those are separate plans: YIELDFIX, BGFIX, ENVFIX)
- Renaming methods or changing interfaces
- Moving transforms to a different class hierarchy
- Performance improvements
- Documentation improvements beyond file-level comments

## Expected Payoff

**Immediate:**
- **Reduced cognitive load**: Developers can focus on one transformation concern at a time (e.g., just variable rewriting) without navigating unrelated code
- **Clearer dependencies**: The 5 modules have minimal cross-dependencies — this makes the data flow explicit
- **Safer modifications**: Changes to pattern matching transforms cannot accidentally affect constant folding transforms

**Downstream (PARSARCH):**
- **Easier navigation**: Finding where `yield` is transformed means opening `transform_control.rb` instead of searching through 1,748 lines
- **Parallel development**: Multiple contributors can work on different transform areas without merge conflicts
- **Testability**: Each module can potentially be unit tested in isolation (future work)

**Technical debt:**
- Resolves the 10-year-old TODO comment: *"Ideally these will be broken out of the Compiler class at some point"*
- Aligns transform layer structure with compile layer structure (both use modular includes)

## Proposed Approach

1. **Analyze cross-dependencies**: Before splitting, analyze which methods call which other methods across concern boundaries to determine optimal ordering and whether any methods need to move together

2. **Create `transform_variables.rb`**: Extract the 7 methods dealing with variable finding and environment rewriting (lines 566-823). These are relatively self-contained.

3. **Create `transform_constants.rb`**: Extract the 5 constant/symbol/operator rewrite methods (lines 446-565). These are pure transformation functions with no dependencies on other transform methods.

4. **Create `transform_patterns.rb`**: Extract `rewrite_pattern_matching` (lines 23-218). This is a large, self-contained method with its own internal helper logic.

5. **Create `transform_procs.rb`**: Extract lambda/proc/argument transform methods (lines 219-404, 1508-1748). These handle function-like constructs.

6. **Create `transform_control.rb`**: Extract the remaining control flow, scoping, and concatenation methods (lines 989-1415). These are the most interconnected and should be extracted last.

7. **Update `compiler.rb`**: Replace the single `require 'transform'` with:
   ```ruby
   require 'transform_patterns'
   require 'transform_procs'
   require 'transform_constants'
   require 'transform_variables'
   require 'transform_control'
   ```

8. **Validate**: Run the full test suite to ensure identical behavior.

## Acceptance Criteria

- [ ] [transform_patterns.rb](../../transform_patterns.rb) exists and contains `rewrite_pattern_matching` method
- [ ] [transform_procs.rb](../../transform_procs.rb) exists and contains `rewrite_lambda`, `rewrite_proc_return`, `rewrite_forward_args`, `rewrite_keyword_args`, `rewrite_default_args`, `convert_ternalt_in_calls`, `group_keyword_arguments`, `rewrite_defined`
- [ ] [transform_constants.rb](../../transform_constants.rb) exists and contains `rewrite_strconst`, `symbol_name`, `rewrite_integer_constant`, `rewrite_symbol_constant`, `rewrite_operators`
- [ ] [transform_variables.rb](../../transform_variables.rb) exists and contains `find_vars`, `find_vars_ary`, `rewrite_env_vars`, `rewrite_let_env`, `in_scopes`, `is_special_name?`, `push_var`
- [ ] [transform_control.rb](../../transform_control.rb) exists and contains remaining methods: `rewrite_range`, `create_concat`, `rewrite_concat`, `build_class_scopes`, `build_class_scopes_for_class`, `flatten_comma`, `rewrite_destruct`, `rewrite_yield`, `rewrite_for`, `setup_global_scope`, `register_constants`, `flatten_deref`, `preprocess`
- [ ] [compiler.rb](../../compiler.rb) requires the 5 new modules instead of `transform`
- [ ] `make selftest` passes with no regressions
- [ ] `make selftest-c` passes with no regressions
- [ ] `make spec` passes with no regressions
- [ ] Total lines across the 5 new files equals the original 1,748 lines in transform.rb (±10 lines for requires/comments)

## Open Questions

- Should `preprocess` remain in `transform_control.rb` or be moved to a separate `transform_preprocess.rb` given that it orchestrates calling other transforms?
- Some methods like `flatten_comma` and `flatten_deref` are general utilities used by multiple transforms — should they go in a `transform_utils.rb` or remain in `transform_control.rb`?
- The original `transform.rb` should either be deleted (clean break) or kept as a meta-loader for backward compatibility (safer transition). Which approach?

## Notes

- The `compile_*.rb` files demonstrate the established pattern: each extends the `Compiler` class with a specific concern, and `compiler.rb` requires them all.
- Method extraction can be done incrementally: one module at a time, validating after each step.
- Git history will be clearer if each new file is created in a separate commit with `git mv`-style tracking (copy original, trim to relevant methods, commit, repeat).

---
*Status: PROPOSAL - Awaiting approval*
