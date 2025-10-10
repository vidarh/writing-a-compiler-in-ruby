#!/bin/bash
# Analyze segfault causes by examining spec files

echo "Analyzing SEGFAULT specs for block parameter usage..."
echo "======================================================="
echo

specs=(
"rubyspec/core/integer/abs_spec.rb"
"rubyspec/core/integer/allbits_spec.rb"
"rubyspec/core/integer/anybits_spec.rb"
"rubyspec/core/integer/bit_and_spec.rb"
"rubyspec/core/integer/bit_length_spec.rb"
"rubyspec/core/integer/bit_or_spec.rb"
"rubyspec/core/integer/bit_xor_spec.rb"
"rubyspec/core/integer/case_compare_spec.rb"
"rubyspec/core/integer/ceildiv_spec.rb"
"rubyspec/core/integer/ceil_spec.rb"
"rubyspec/core/integer/chr_spec.rb"
"rubyspec/core/integer/coerce_spec.rb"
"rubyspec/core/integer/comparison_spec.rb"
"rubyspec/core/integer/divide_spec.rb"
"rubyspec/core/integer/divmod_spec.rb"
"rubyspec/core/integer/div_spec.rb"
"rubyspec/core/integer/downto_spec.rb"
"rubyspec/core/integer/element_reference_spec.rb"
"rubyspec/core/integer/equal_value_spec.rb"
"rubyspec/core/integer/exponent_spec.rb"
"rubyspec/core/integer/fdiv_spec.rb"
"rubyspec/core/integer/floor_spec.rb"
"rubyspec/core/integer/left_shift_spec.rb"
"rubyspec/core/integer/lte_spec.rb"
"rubyspec/core/integer/magnitude_spec.rb"
"rubyspec/core/integer/minus_spec.rb"
"rubyspec/core/integer/modulo_spec.rb"
"rubyspec/core/integer/multiply_spec.rb"
"rubyspec/core/integer/nobits_spec.rb"
"rubyspec/core/integer/numerator_spec.rb"
"rubyspec/core/integer/plus_spec.rb"
"rubyspec/core/integer/pow_spec.rb"
"rubyspec/core/integer/rationalize_spec.rb"
"rubyspec/core/integer/remainder_spec.rb"
"rubyspec/core/integer/right_shift_spec.rb"
"rubyspec/core/integer/round_spec.rb"
"rubyspec/core/integer/size_spec.rb"
"rubyspec/core/integer/sqrt_spec.rb"
"rubyspec/core/integer/times_spec.rb"
"rubyspec/core/integer/to_f_spec.rb"
"rubyspec/core/integer/try_convert_spec.rb"
"rubyspec/core/integer/uminus_spec.rb"
"rubyspec/core/integer/upto_spec.rb"
)

uses_blocks=0
uses_shared=0
uses_send=0
uses_lambda=0

for spec in "${specs[@]}"; do
    if [ -f "$spec" ]; then
        has_block=$(grep -c "\.each do |" "$spec" 2>/dev/null || echo 0)
        has_shared=$(grep -c "it_behaves_like\|shared:" "$spec" 2>/dev/null || echo 0)
        has_send=$(grep -c "\.send(" "$spec" 2>/dev/null || echo 0)
        has_lambda=$(grep -c " lambda \| -> " "$spec" 2>/dev/null || echo 0)
        
        if [ "$has_block" -gt 0 ] || [ "$has_shared" -gt 0 ]; then
            echo "$(basename $spec):"
            [ "$has_block" -gt 0 ] && echo "  - Uses blocks: YES" && ((uses_blocks++))
            [ "$has_shared" -gt 0 ] && echo "  - Uses shared specs: YES" && ((uses_shared++))
            [ "$has_send" -gt 0 ] && echo "  - Uses .send: YES" && ((uses_send++))
            [ "$has_lambda" -gt 0 ] && echo "  - Uses lambda: YES" && ((uses_lambda++))
        fi
    fi
done

echo
echo "Summary:"
echo "  Specs using blocks: $uses_blocks"
echo "  Specs using shared specs: $uses_shared"  
echo "  Specs using .send: $uses_send"
echo "  Specs using lambda: $uses_lambda"
