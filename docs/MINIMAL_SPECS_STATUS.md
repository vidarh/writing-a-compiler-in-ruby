# Minimal Specs for 29 Compile Failures - Status

**Date**: 2025-11-18

## Summary

Created minimal spec files for all 29 rubyspec/language/ compile failures.
Each spec file is named to indicate the error type and maps to its corresponding rubyspec file.

## Spec Files Created

| # | Minimal Spec File | Rubyspec File | Error Type | Status |
|---|-------------------|---------------|------------|--------|
| 1 | array_index_splat_begin_spec.rb | assignments_spec.rb | Syntax error (splat+begin) | ✅ VERIFIED |
| 2 | optional_assignments_splat_begin_spec.rb | optional_assignments_spec.rb | Syntax error (splat+begin) | ✅ VERIFIED |
| 3 | regex_after_semicolon_spec.rb | case_spec.rb | Missing value (/a/ as division) | ✅ VERIFIED |
| 4 | class_superclass_atom_spec.rb | class_spec.rb | Parse error (superclass) | ✅ FIXED |
| 5 | constants_nested_assign_spec.rb | constants_spec.rb | compile_exp warning | ⚠️ PARTIAL |
| 6 | def_keyword_args_spec.rb | def_spec.rb | Arg.name internal error | ❌ NEEDS FIX |
| 7 | for_closure_link_error_spec.rb | for_spec.rb | undefined __env__/__closure__ | ✅ FIXED |
| 8 | keyword_arg_shorthand_hash_spec.rb | hash_spec.rb | Missing value ({a:} shorthand) | ✅ VERIFIED |
| 9 | heredoc_parsing_error_spec.rb | heredoc_spec.rb | Unterminated heredoc | ⚠️ PARTIAL |
| 10 | keyword_arguments_full_spec.rb | keyword_arguments_spec.rb | Keyword arg shorthand | 🔄 TODO |
| 11 | metaclass_assembly_error_spec.rb | metaclass_spec.rb | junk [:sexp | 🔄 TODO |
| 12 | method_keyword_args_spec.rb | method_spec.rb | Keyword arg shorthand | 🔄 TODO |
| 13 | module_nested_const_spec.rb | module_spec.rb | Nested const | 🔄 TODO |
| 14 | pattern_matching_spec.rb | pattern_matching_spec.rb | Ruby 2.7+ feature | 🔄 TODO |
| 15 | precedence_nested_const_spec.rb | precedence_spec.rb | Nested const | 🔄 TODO |
| 16 | predefined_duplicate_symbol_spec.rb | predefined_spec.rb | Duplicate symbol | 🔄 TODO |
| 17 | private_assembly_error_spec.rb | private_spec.rb | junk [:sexp | 🔄 TODO |
| 18 | regexp_encoding_block_error_spec.rb | regexp/encoding_spec.rb | Expected 'end' | 🔄 TODO |
| 19 | regexp_escapes_regalloc_error_spec.rb | regexp/escapes_spec.rb | divided by 0 | 🔄 TODO |
| 20 | rescue_safe_navigation_spec.rb | rescue_spec.rb | Safe nav in rescue | ✅ VERIFIED |
| 21 | return_global_var_spec.rb | return_spec.rb | Global var scope | ✅ VERIFIED |
| 22 | safe_navigator_spec.rb | safe_navigator_spec.rb | &. operator | ✅ VERIFIED |
| 23 | send_closure_link_error_spec.rb | send_spec.rb | undefined __env__ | 🔄 TODO |
| 24 | singleton_class_assembly_error_spec.rb | singleton_class_spec.rb | junk [:sexp | 🔄 TODO |
| 25 | super_closure_link_error_spec.rb | super_spec.rb | undefined Module | 🔄 TODO |
| 26 | symbol_expression_reduction_error_spec.rb | symbol_spec.rb | Expression reduction | 🔄 TODO |
| 27 | until_ternary_next_spec.rb | until_spec.rb | Ternary+next | ✅ VERIFIED |
| 28 | anonymous_splat_assignment_spec.rb | variables_spec.rb | Anonymous splat | ✅ VERIFIED |
| 29 | while_parenthesized_break_spec.rb | while_spec.rb | Parenthesized break | ✅ VERIFIED |

## Notes

- ✅ VERIFIED: Spec reproduces the exact error from rubyspec
- ✅ FIXED: Spec was corrected to match rubyspec error
- ⚠️ PARTIAL: Spec tests related functionality but doesn't trigger exact error
- ❌ NEEDS FIX: Spec needs to be corrected
- 🔄 TODO: Not yet verified

## Known Issues

1. **constants_nested_assign_spec.rb**: The "compile_exp" warning is non-fatal and appears to require very specific eigenclass+constant scenarios that are hard to isolate.

2. **heredoc_parsing_error_spec.rb**: The actual rubyspec has malformed heredoc syntax that causes tokenizer failure. Cannot create a valid Ruby spec file that reproduces invalid syntax.

3. **def_keyword_args_spec.rb**: Currently triggers {a:} hash shorthand error instead of "Arg.name" internal error.

## Next Steps

1. Verify remaining 19 specs (marked TODO)
2. Fix spec #6 (def_keyword_args)
3. Document any additional partial matches
