PARSARCH

# Parser Architecture Unification

Unify control flow parsing so that all control structures (if, while, unless, until, begin, for) are expressions handled through the shunting yard parser, enabling method chaining, arithmetic, and all other expression contexts on control flow return values.

## Vision

Every Ruby control structure is a first-class expression. Writing `if true; 42; end.to_s`, `[if true; 1; end, 2]`, or `puts(while x; break y; end)` all work correctly because control flow keywords are parsed through the shunting yard like any other expression. The parser has a single code path for control structures rather than the current split between statement-level parsing (parse_defexp) and expression-level parsing (shunting yard). This eliminates an entire class of parser bugs and unblocks 5+ language specs.

## Why This Matters

This is the deepest architectural blocker in the parser. Control structures are currently parsed in two separate places with different behavior, creating a fundamental inconsistency: `x = if true; 42; end` works but `if true; 42; end.to_s` does not. Three prior attempts to fix this have failed, each revealing a different aspect of the context-detection problem (distinguishing "expression value context" from "statement sequence context" across nested shunting yard instances). Solving this once and correctly would unblock metaclass_spec, symbol_spec, while_spec, and other language specs, while also eliminating a major source of parser fragility.

## Sources

Where this goal was discovered:
- docs/control_flow_as_expressions.md: Comprehensive 184-line document describing the problem, three failed fix attempts, architectural analysis, and solution approach -- the most detailed analysis of any single issue in the project
- docs/control_flow_as_expressions.md (lines 46-51): Lists affected specs: case_spec, metaclass_spec, symbol_spec, unless_spec, while_spec
- docs/control_flow_as_expressions.md (lines 76-77): User guidance on solution approach: "ensure the shunting yard parser recognises the first value as a legal position for the control flow keywords"
- docs/control_flow_as_expressions.md (lines 115-147): Documents three failed attempts and why each failed, providing crucial negative knowledge
- spec/ directory: Multiple spec files (control_flow_expressions_spec.rb, if_end_should_spec.rb, unless_end_should_spec.rb, until_end_should_spec.rb, while_end_chain_spec.rb, for_end_method_chain_spec.rb, all_control_flow_end_should_spec.rb) test various aspects of this problem

## Related Goals

- [COMPLANG](COMPLANG-compiler-advancement.md): This parser fix directly unblocks 5+ language spec files and likely improves individual test pass rate for many more
- [SELFHOST](SELFHOST-clean-bootstrap.md): A unified parser is simpler and more correct, reducing the set of Ruby constructs that must be avoided in compiler source

## Potential Plans

**Note:** This goal leans heavily on `docs/control_flow_as_expressions.md` and specific spec files, which may be outdated — the parser has evolved since these were written. A good first plan would be to validate the current state: run the referenced spec files, check whether the documented failures still reproduce, and update or retire stale documents accordingly. This prevents wasted effort on problems that may already be partially or fully solved.

Ideas for incremental plans that would advance this goal:
- Validate referenced documents and specs against current compiler state: run each listed spec, confirm which failures still reproduce, and update docs/control_flow_as_expressions.md to reflect current reality
- Analyze how nested shunting yard instances are created during parsing and design a context-passing mechanism (parameter or state flag) to distinguish expression-value from statement-sequence contexts
- Prototype adding `if`/`unless` to @escape_tokens with a targeted fix for the body-parsing issue that caused Attempt 1 to fail
- Implement the user's suggested approach: make the shunting yard recognize control flow keywords in first-value position, then remove control flow from parse_defexp
- Create a comprehensive test suite for control-flow-as-expression edge cases before attempting the fix, ensuring no regression pathway is missed

---
*Status: GOAL*
