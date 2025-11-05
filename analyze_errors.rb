#!/usr/bin/env ruby

# Analyze compilation errors in language specs
errors = Hash.new(0)

File.readlines('docs/language_spec_failures.txt').each do |line|
  if line =~ /Parse error: (.+?)$/
    error = $1.strip
    # Normalize some common patterns
    error = error.gsub(/Expected: '[^']*'/, "Expected: 'X'")
    error = error.gsub(/for '[^']*' block/, "for 'X' block")
    errors[error] += 1
  elsif line =~ /Module not found:|undefined method|wrong number of arguments/
    errors[line.strip] += 1
  end
end

puts "Top compilation errors:"
errors.sort_by { |k, v| -v }.take(15).each do |error, count|
  puts "#{count}x: #{error}"
end
