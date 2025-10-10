#!/usr/bin/env ruby

segfault_specs = %w[
  abs_spec.rb allbits_spec.rb anybits_spec.rb bit_and_spec.rb
  bit_length_spec.rb bit_or_spec.rb bit_xor_spec.rb case_compare_spec.rb
  ceildiv_spec.rb ceil_spec.rb chr_spec.rb coerce_spec.rb
  comparison_spec.rb divide_spec.rb divmod_spec.rb div_spec.rb
  downto_spec.rb element_reference_spec.rb equal_value_spec.rb
  exponent_spec.rb fdiv_spec.rb floor_spec.rb left_shift_spec.rb
  lte_spec.rb magnitude_spec.rb minus_spec.rb modulo_spec.rb
  multiply_spec.rb nobits_spec.rb numerator_spec.rb plus_spec.rb
  pow_spec.rb rationalize_spec.rb remainder_spec.rb right_shift_spec.rb
  round_spec.rb size_spec.rb sqrt_spec.rb times_spec.rb
  to_f_spec.rb try_convert_spec.rb uminus_spec.rb upto_spec.rb
]

categories = {
  blocks: [],
  lambda: [],
  missing_methods: [],
  other: []
}

segfault_specs.each do |spec|
  path = "rubyspec/core/integer/#{spec}"
  next unless File.exist?(path)
  
  content = File.read(path)
  
  # Check for block parameters in the spec itself
  has_blocks = content.match?(/\.each do \||\.times do \||\.upto.*do \||\.downto.*do \|/)
  
  # Check for lambda syntax
  has_lambda = content.match?(/ -> /)
  
  # Check for shared specs (many contain blocks)
  has_shared = content.match?(/it_behaves_like/)
  
  if has_blocks || has_shared
    categories[:blocks] << spec
  end
  
  if has_lambda
    categories[:lambda] << spec
  end
end

puts "=== SEGFAULT CATEGORIZATION ==="
puts
puts "Specs likely affected by BLOCK PARAMETER BUG (#{categories[:blocks].size}):"
categories[:blocks].each { |s| puts "  - #{s}" }
puts
puts "Specs using LAMBDA SYNTAX (#{categories[:lambda].size}):"
categories[:lambda].each { |s| puts "  - #{s}" }
puts
puts "Specs with BOTH issues (#{(categories[:blocks] & categories[:lambda]).size}):"
(categories[:blocks] & categories[:lambda]).each { |s| puts "  - #{s}" }
puts
puts "Specs with ONLY blocks (#{(categories[:blocks] - categories[:lambda]).size}):"
(categories[:blocks] - categories[:lambda]).each { |s| puts "  - #{s}" }
