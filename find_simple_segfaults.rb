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

simple = []
segfault_specs.each do |spec|
  path = "rubyspec/core/integer/#{spec}"
  next unless File.exist?(path)
  
  content = File.read(path)
  
  has_blocks = content.match?(/\.each do \||\.times do \||\.upto.*do \||\.downto.*do \|/)
  has_lambda = content.match?(/ -> /)
  has_shared = content.match?(/it_behaves_like/)
  
  if !has_blocks && !has_lambda && !has_shared
    simple << spec
  end
end

puts "Specs with NO blocks, NO lambda, NO shared (#{simple.size}):"
simple.each { |s| puts "  - #{s}" }
