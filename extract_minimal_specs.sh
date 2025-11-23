#!/bin/bash
# Extract minimal failing code from each COMPILE FAIL spec

SPECS=(
  "rubyspec/language/assignments_spec.rb"
  "rubyspec/language/case_spec.rb"
  "rubyspec/language/class_spec.rb"
  "rubyspec/language/constants_spec.rb"
  "rubyspec/language/def_spec.rb"
  "rubyspec/language/for_spec.rb"
  "rubyspec/language/hash_spec.rb"
  "rubyspec/language/heredoc_spec.rb"
  "rubyspec/language/keyword_arguments_spec.rb"
  "rubyspec/language/metaclass_spec.rb"
  "rubyspec/language/method_spec.rb"
  "rubyspec/language/module_spec.rb"
  "rubyspec/language/optional_assignments_spec.rb"
  "rubyspec/language/pattern_matching_spec.rb"
  "rubyspec/language/precedence_spec.rb"
  "rubyspec/language/predefined_spec.rb"
  "rubyspec/language/private_spec.rb"
  "rubyspec/language/regexp/encoding_spec.rb"
  "rubyspec/language/regexp/escapes_spec.rb"
  "rubyspec/language/rescue_spec.rb"
  "rubyspec/language/return_spec.rb"
  "rubyspec/language/safe_navigator_spec.rb"
  "rubyspec/language/send_spec.rb"
  "rubyspec/language/singleton_class_spec.rb"
  "rubyspec/language/super_spec.rb"
  "rubyspec/language/symbol_spec.rb"
  "rubyspec/language/until_spec.rb"
  "rubyspec/language/variables_spec.rb"
  "rubyspec/language/while_spec.rb"
)

for spec in "${SPECS[@]}"; do
  echo "Processing $spec..."
  basename=$(basename "$spec" .rb)

  # Run the spec to generate rubyspec_temp file
  ./run_rubyspec "$spec" >/dev/null 2>&1

  temp_file="rubyspec_temp_${basename}.rb"

  if [ -f "$temp_file" ]; then
    echo "  Found $temp_file, extracting minimal case..."
    # Try to bisect - use a generic error pattern
    ruby bisect-parse-error.rb "$temp_file" "Error" > "minimal_${basename}.rb" 2>&1
  fi
done
