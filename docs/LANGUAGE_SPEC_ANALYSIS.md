# Language Spec Failure Analysis

**Date**: 2025-11-01 (Session 41)
**Source**: `./run_rubyspec rubyspec/language/`

## Summary Statistics

- **Total spec files**: 79
- **COMPILE FAIL**: 72 (91%)
- **FAIL** (runtime): 5 (6%)
- **CRASH**: 2 (3%)
- **PASS**: 0 (0%)
- **Pass rate**: 8% (4/45 tests pass)

## Status: UNCHARTED TERRITORY

This represents the Ruby **language features** - syntax, control flow, special forms, etc.
Most failures are **parser/compiler issues**, not runtime bugs.

## Specs That Compile (7 total)

These specs successfully compile but have runtime failures:

1. **comment_spec.rb** (P:0 F:1) - Comments
2. **not_spec.rb** (P:4 F:12) - `not` keyword
3. **predefined/toplevel_binding_spec.rb** (P:0 F:10) - $TOPLEVEL_BINDING
4. **regexp/empty_checks_spec.rb** (P:0 F:8) - Empty regex checks  
5. **regexp/subexpression_call_spec.rb** (P:0 F:10) - Regex subexpressions

**Note**: All regex specs likely fail due to missing regex implementation (not parser).

## Specs That Crash (2 total)

1. **order_spec.rb** - CRASH (evaluation order)
2. **safe_spec.rb** - CRASH ($SAFE variable)

## Compilation Failures By Category (72 total)

**IMPORTANT**: These categories are preliminary. Further investigation needed.

### Category 1: Core Language Features (High Priority)
- **alias_spec.rb** - Method aliasing
- **assignments_spec.rb** - Various assignment forms  
- **block_spec.rb** - Block syntax and semantics
- **case_spec.rb** - Case/when statements
- **class_spec.rb** - Class definitions
- **def_spec.rb** - Method definitions
- **hash_spec.rb** - Hash literals
- **if_spec.rb** - If/elsif/else conditionals
- **lambda_spec.rb** - Lambda syntax
- **loop_spec.rb** - Loop constructs
- **method_spec.rb** - Method features
- **module_spec.rb** - Module definitions
- **proc_spec.rb** - Proc objects
- **unless_spec.rb** - Unless conditionals
- **until_spec.rb** - Until loops
- **variables_spec.rb** - Variable scoping
- **while_spec.rb** - While loops

### Category 2: Control Flow
- **break_spec.rb** - Break statements
- **next_spec.rb** - Next statements  
- **redo_spec.rb** - Redo statements
- **return_spec.rb** - Return statements
- **throw_spec.rb** - Throw/catch

### Category 3: Exception Handling
- **ensure_spec.rb** - Ensure blocks
- **rescue_spec.rb** - Rescue blocks
- **retry_spec.rb** - Retry in rescue

### Category 4: Advanced Features (Lower Priority)
- **and_spec.rb** - `and` keyword
- **or_spec.rb** - `or` keyword
- **BEGIN_spec.rb** - BEGIN blocks
- **END_spec.rb** - END blocks
- **class_variable_spec.rb** - @@ class variables
- **constants_spec.rb** - Constant definitions
- **defined_spec.rb** - `defined?` keyword
- **for_spec.rb** - For loops
- **keyword_arguments_spec.rb** - Keyword args
- **metaclass_spec.rb** - Metaclass/eigenclass
- **numbered_parameters_spec.rb** - Numbered block params (_1, _2)
- **optional_assignments_spec.rb** - ||=, &&=
- **pattern_matching_spec.rb** - Pattern matching (Ruby 2.7+)
- **precedence_spec.rb** - Operator precedence
- **range_spec.rb** - Range literals
- **safe_navigator_spec.rb** - &. operator
- **singleton_class_spec.rb** - Singleton classes
- **super_spec.rb** - Super keyword
- **undef_spec.rb** - Undef keyword
- **yield_spec.rb** - Yield keyword

### Category 5: String/Regex Features
- **array_spec.rb** - Array literals (may include complex syntax)
- **encoding_spec.rb** - String encoding
- **heredoc_spec.rb** - Heredoc syntax
- **match_spec.rb** - Match operator (=~)
- **numbers_spec.rb** - Number literals
- **string_spec.rb** - String literals
- **symbol_spec.rb** - Symbol literals
- **regexp/** (8 specs) - Regular expressions

### Category 6: Special Variables/Features
- **delegation_spec.rb** - Method delegation
- **execution_spec.rb** - Backticks/system execution
- **file_spec.rb** - __FILE__ constant
- **line_spec.rb** - __LINE__ constant  
- **magic_comment_spec.rb** - Magic comments
- **predefined/** - Predefined variables
- **private_spec.rb** - Private methods
- **send_spec.rb** - #send method
- **source_encoding_spec.rb** - __ENCODING__

## Next Steps (DO NOT IMPLEMENT YET!)

1. **Investigate compile failures** - Sample 3-5 specs from Category 1
2. **Categorize error types** - Syntax errors, missing keywords, unsupported features
3. **Improve error reporting** - Make parser errors more helpful
4. **Create minimal test cases** - Isolate each issue
5. **Document parser limitations** - What syntax is/isn't supported
6. **Prioritize fixes** - Start with most common/impactful issues

## Notes

- Most failures are likely **parser limitations**, not bugs
- Some may be **missing language features** (heredoc, pattern matching, etc.)
- A few may be **compiler limitations** (BEGIN/END blocks, etc.)
- Need to examine actual error messages to categorize properly
- Improving error messages should be first priority

