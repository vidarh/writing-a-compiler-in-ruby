#!/usr/bin/env ruby
# Analyze compilation errors in language specs after eigenclass fix

require 'open3'

specs = Dir.glob('rubyspec/language/**/*_spec.rb').sort

errors = Hash.new(0)
error_examples = Hash.new { |h, k| h[k] = [] }

specs.each do |spec|
  cmd = "./compile #{spec} -I . 2>&1"
  output, status = Open3.capture2(cmd)

  if status.exitstatus != 0
    # Extract the error message
    if output =~ /Parse error: (.+?)$/
      error = $1.strip
      # Normalize the error
      error = error.gsub(/:[0-9]+/, ':N')  # Replace line numbers
      error = error.gsub(/'[^']*'/, "'X'")  # Replace quoted strings
      error = error.gsub(/`[^`]*`/, "`X`")  # Replace backticked strings

      errors[error] += 1
      error_examples[error] << File.basename(spec) if error_examples[error].size < 3
    elsif output =~ /Compiler error: (.+?)$/
      error = $1.strip
      errors[error] += 1
      error_examples[error] << File.basename(spec) if error_examples[error].size < 3
    elsif output =~ /(Expected:.+?)$/
      error = $1.strip
      errors[error] += 1
      error_examples[error] << File.basename(spec) if error_examples[error].size < 3
    end
  end
end

puts "=" * 80
puts "LANGUAGE SPEC COMPILATION ERROR ANALYSIS (After Eigenclass Fix)"
puts "=" * 80
puts

sorted_errors = errors.sort_by { |k, v| -v }

sorted_errors.each_with_index do |(error, count), index|
  puts "#{index + 1}. [#{count} specs] #{error}"
  puts "   Examples: #{error_examples[error].join(', ')}"
  puts
end

puts "=" * 80
puts "Total unique error patterns: #{errors.size}"
puts "Total specs with compilation errors: #{errors.values.sum}"
