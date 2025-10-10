segfault_specs = %w[
  bit_length_spec.rb ceildiv_spec.rb size_spec.rb to_f_spec.rb
  allbits_spec.rb anybits_spec.rb nobits_spec.rb
  bit_and_spec.rb bit_or_spec.rb bit_xor_spec.rb
  coerce_spec.rb comparison_spec.rb divmod_spec.rb div_spec.rb
  downto_spec.rb element_reference_spec.rb fdiv_spec.rb
  left_shift_spec.rb remainder_spec.rb right_shift_spec.rb
  sqrt_spec.rb try_convert_spec.rb
]

segfault_specs.each do |spec|
  path = "rubyspec/core/integer/#{spec}"
  next unless File.exist?(path)
  
  content = File.read(path)
  
  has_context = content.match?(/context /)
  has_lambda = content.match?(/ -> /)
  has_blocks = content.match?(/\.each do \||\.times do \||\.upto.*do \|/)
  has_shared = content.match?(/it_behaves_like/)
  
  if has_context && !has_lambda && !has_blocks && !has_shared
    puts "#{spec}: context only"
  end
end
