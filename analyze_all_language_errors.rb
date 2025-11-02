#!/usr/bin/env ruby
# Analyze all language spec compilation errors to find most common patterns

puts "Analyzing all language spec compilation errors..."
puts "=" * 60

# Find all language spec temp files (created by run_rubyspec)
temp_files = Dir.glob("rubyspec_temp_*_spec.rb").sort

# If no temp files exist, we need to create them by running the specs
if temp_files.empty?
  puts "No temp files found. Please run: ./run_rubyspec rubyspec/language/"
  exit 1
end

errors = {}
compiling_specs = []
total = 0

temp_files.each do |spec|
  total += 1
  spec_name = File.basename(spec, ".rb").sub("rubyspec_temp_", "")

  # Skip non-language specs
  next unless spec_name.match(/_spec$/)

  # Try to compile and capture error
  output = `ruby -I. driver.rb #{spec} -I. 2>&1`

  if $?.success?
    compiling_specs << spec_name
    next
  end

  # Extract error message
  error_msg = nil

  # Try different error patterns
  if output =~ /Parse error: (.+?)(?:\(RuntimeError\)|$)/m
    error_msg = $1.strip
  elsif output =~ /Compiler error: (.+?)(?:\(RuntimeError\)|$)/m
    error_msg = $1.strip
  elsif output =~ /(Expected: .+?)(?:\(RuntimeError\)|$)/m
    error_msg = $1.strip
  elsif output =~ /(Missing value .+?)(?:\(RuntimeError\)|$)/m
    error_msg = $1.strip
  elsif output =~ /(Unable to .+?)(?:\(RuntimeError\)|$)/m
    error_msg = $1.strip
  elsif output =~ /undefined reference to '(\w+)'/
    error_msg = "Link error: undefined reference to '#{$1}'"
  else
    # Unknown error format
    error_msg = output.lines.first&.strip || "Unknown error"
  end

  # Normalize error message (remove file-specific details)
  normalized = error_msg
    .gsub(/\/home\/[^\s]+\//, "")
    .gsub(/rubyspec_temp_\w+_spec\.rb/, "<spec>")
    .gsub(/:\d+:\d+:/, ":[LINE]:[COL]:")
    .gsub(/line \d+/, "line N")
    .gsub(/\d+ passed/, "N passed")
    .gsub(/got \w+/, "got TYPE")

  # Truncate very long errors
  normalized = normalized[0...150] if normalized.length > 150

  errors[normalized] ||= []
  errors[normalized] << spec_name
end

puts
puts "=" * 60
puts "SUMMARY"
puts "=" * 60
puts "Total language specs analyzed: #{total}"
puts "Specs that COMPILE successfully: #{compiling_specs.size}"
puts "Specs with compilation errors: #{errors.size}"
puts

if compiling_specs.any?
  puts "✓ Specs that compile:"
  compiling_specs.each { |s| puts "  - #{s}" }
  puts
end

puts "=" * 60
puts "ERROR FREQUENCY ANALYSIS"
puts "=" * 60
puts

# Sort by frequency (most common first)
sorted_errors = errors.sort_by { |msg, specs| -specs.size }

sorted_errors.each_with_index do |(msg, specs), idx|
  puts "#{idx + 1}. [#{specs.size} specs] #{msg}"
  puts "   Affected: #{specs.join(', ')}"
  puts
end

puts "=" * 60
puts "CATEGORIZED RECOMMENDATIONS"
puts "=" * 60
puts

# Categorize errors by type
categories = {
  "Parser - include keyword" => [],
  "Parser - other" => [],
  "Compiler - assignment" => [],
  "Compiler - other" => [],
  "Shunting yard" => [],
  "Link errors" => [],
  "Unknown" => []
}

sorted_errors.each do |msg, specs|
  if msg.include?("name of module to include")
    categories["Parser - include keyword"] << [msg, specs]
  elsif msg.include?("Parse error") || msg.include?("Expected:")
    categories["Parser - other"] << [msg, specs]
  elsif msg.include?("assignment")
    categories["Compiler - assignment"] << [msg, specs]
  elsif msg.include?("Compiler error")
    categories["Compiler - other"] << [msg, specs]
  elsif msg.include?("Missing value") || msg.include?("requires two values")
    categories["Shunting yard"] << [msg, specs]
  elsif msg.include?("undefined reference")
    categories["Link errors"] << [msg, specs]
  else
    categories["Unknown"] << [msg, specs]
  end
end

categories.each do |category, items|
  next if items.empty?

  total_specs = items.sum { |msg, specs| specs.size }
  puts "#{category}: #{total_specs} specs"
  items.each do |msg, specs|
    puts "  [#{specs.size}] #{msg[0...80]}"
  end
  puts
end

puts "=" * 60
puts "RECOMMENDED FIX ORDER (by impact × ease)"
puts "=" * 60
puts

# Calculate priority score (frequency × estimated ease)
# Ease scale: 1 (very hard) to 5 (very easy)
priorities = []

sorted_errors.each do |msg, specs|
  ease = 3 # default medium

  if msg.include?("name of module to include")
    ease = 4 # Easy: just remove keyword, add method
    priorities << [specs.size * ease, "Remove 'include' keyword, implement as method", specs.size, ease]
  elsif msg.include?("assignment") && msg.include?("subexpr")
    ease = 2 # Hard: requires destructuring implementation
    priorities << [specs.size * ease, "Implement multiple assignment/destructuring", specs.size, ease]
  elsif msg.include?("Missing value") || msg.include?("requires two values")
    ease = 2 # Medium-hard: shunting yard bugs
    priorities << [specs.size * ease, "Fix shunting yard: #{msg[0...40]}", specs.size, ease]
  elsif msg.include?("undefined reference")
    ease = 5 # Very easy: just add stub classes
    priorities << [specs.size * ease, "Add missing exception/class stubs", specs.size, ease]
  else
    priorities << [specs.size * ease, msg[0...60], specs.size, ease]
  end
end

priorities.sort_by! { |score, desc, count, ease| -score }

priorities.first(10).each_with_index do |(score, desc, count, ease), idx|
  puts "#{idx + 1}. [Score: #{score}] #{desc}"
  puts "   Impact: #{count} specs, Ease: #{ease}/5"
  puts
end
