#!/bin/bash
# Verify all 29 minimal specs reproduce the correct errors

specs=(
  "spec/array_index_splat_begin_spec.rb:rubyspec/language/assignments_spec.rb"
  "spec/optional_assignments_splat_begin_spec.rb:rubyspec/language/optional_assignments_spec.rb"
  "spec/regex_after_semicolon_spec.rb:rubyspec/language/case_spec.rb"
  "spec/class_superclass_atom_spec.rb:rubyspec/language/class_spec.rb"
  "spec/constants_nested_assign_spec.rb:rubyspec/language/constants_spec.rb"
  "spec/def_keyword_args_spec.rb:rubyspec/language/def_spec.rb"
  "spec/for_closure_link_error_spec.rb:rubyspec/language/for_spec.rb"
  "spec/keyword_arg_shorthand_hash_spec.rb:rubyspec/language/hash_spec.rb"
  "spec/heredoc_parsing_error_spec.rb:rubyspec/language/heredoc_spec.rb"
  "spec/keyword_arguments_full_spec.rb:rubyspec/language/keyword_arguments_spec.rb"
  "spec/metaclass_assembly_error_spec.rb:rubyspec/language/metaclass_spec.rb"
  "spec/method_keyword_args_spec.rb:rubyspec/language/method_spec.rb"
  "spec/module_nested_const_spec.rb:rubyspec/language/module_spec.rb"
  "spec/pattern_matching_spec.rb:rubyspec/language/pattern_matching_spec.rb"
  "spec/precedence_nested_const_spec.rb:rubyspec/language/precedence_spec.rb"
  "spec/predefined_duplicate_symbol_spec.rb:rubyspec/language/predefined_spec.rb"
  "spec/private_assembly_error_spec.rb:rubyspec/language/private_spec.rb"
  "spec/regexp_encoding_block_error_spec.rb:rubyspec/language/regexp/encoding_spec.rb"
  "spec/regexp_escapes_regalloc_error_spec.rb:rubyspec/language/regexp/escapes_spec.rb"
  "spec/rescue_safe_navigation_spec.rb:rubyspec/language/rescue_spec.rb"
  "spec/return_global_var_spec.rb:rubyspec/language/return_spec.rb"
  "spec/safe_navigator_spec.rb:rubyspec/language/safe_navigator_spec.rb"
  "spec/send_closure_link_error_spec.rb:rubyspec/language/send_spec.rb"
  "spec/singleton_class_assembly_error_spec.rb:rubyspec/language/singleton_class_spec.rb"
  "spec/super_closure_link_error_spec.rb:rubyspec/language/super_spec.rb"
  "spec/symbol_expression_reduction_error_spec.rb:rubyspec/language/symbol_spec.rb"
  "spec/until_ternary_next_spec.rb:rubyspec/language/until_spec.rb"
  "spec/anonymous_splat_assignment_spec.rb:rubyspec/language/variables_spec.rb"
  "spec/while_parenthesized_break_spec.rb:rubyspec/language/while_spec.rb"
)

echo "=== Verifying all 29 minimal specs ==="
echo ""

for pair in "${specs[@]}"; do
  spec_file="${pair%%:*}"
  rubyspec_file="${pair##*:}"
  
  echo "Testing: $spec_file"
  echo "  Should match: $rubyspec_file"
  
  # Get error from minimal spec
  minimal_error=$(./run_rubyspec "$spec_file" 2>&1 | grep -E "Compilation failed|Error|undefined|junk|Unterminated|Missing|divided" | head -3)
  
  # Get error from rubyspec
  rubyspec_error=$(./run_rubyspec "$rubyspec_file" 2>&1 | grep -E "Compilation failed|Error|undefined|junk|Unterminated|Missing|divided" | head -3)
  
  echo "  Minimal: $minimal_error"
  echo "  Rubyspec: $rubyspec_error"
  echo ""
done
