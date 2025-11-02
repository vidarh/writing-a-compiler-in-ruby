#!/usr/bin/env ruby
# Analyze all language spec compilation errors to find most common patterns

puts "Analyzing all language spec compilation errors..."
puts "=" * 60

# Get list of actual language spec files (including subdirectories)
language_specs = Dir.glob("rubyspec/language/**/*_spec.rb").sort

puts "Found #{language_specs.size} language spec files"
puts

errors = {}
compiling_specs = []
passing_specs = []
failing_specs = []
total = 0

language_specs.each do |spec_path|
  total += 1
  spec_name = File.basename(spec_path, ".rb")

  print "Analyzing #{spec_name}... "

  # Run the spec and capture output
  output = `./run_rubyspec #{spec_path} 2>&1`
  exit_status = $?.exitstatus

  # Check if it compiled
  if output =~ /(\d+) spec files?: (\d+) passed, (\d+) failed, (\d+) errors?/
    passed = $2.to_i
    failed = $3.to_i
    errors = $4.to_i

    if failed == 0 && errors == 0
      puts "PASS (#{passed} tests)"
      passing_specs << spec_name
      next
    elsif passed > 0
      puts "PARTIAL (P:#{passed} F:#{failed} E:#{errors})"
      failing_specs << spec_name
      next
    else
      puts "FAIL (all tests failed)"
      failing_specs << spec_name
      next
    end
  end

  # Check for compilation errors
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
  elsif output =~ /([^:]+\.rb:\d+:in `[^']+': .+? \([A-Z]\w+Error\))/
    error_msg = $1.strip
  else
    # Unknown error format
    error_msg = output.lines.first&.strip || "Unknown error"
  end

  puts "COMPILE ERROR"

  # Normalize error message (remove file-specific details)
  normalized = error_msg
    .gsub(/\/home\/[^\s]+\//, "")
    .gsub(/rubyspec_temp_\w+_spec\.rb/, "<spec>")
    .gsub(/rubyspec\/language\/\w+_spec\.rb/, "<spec>")
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
puts "Specs that PASS all tests: #{passing_specs.size}"
puts "Specs that RUN but have failures: #{failing_specs.size}"
puts "Specs with compilation errors: #{errors.size}"
puts

if passing_specs.any?
  puts "✓ Specs that pass:"
  passing_specs.each { |s| puts "  - #{s}" }
  puts
end

if failing_specs.any?
  puts "⚠ Specs that run but have test failures:"
  failing_specs.each { |s| puts "  - #{s}" }
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
  "Parser - other" => [],
  "Compiler - assignment" => [],
  "Shunting yard" => [],
  "Link errors" => [],
  "Internal errors" => [],
  "Unknown" => []
}

sorted_errors.each do |msg, specs|
  if msg.include?("Parse error") || msg.include?("Expected:")
    categories["Parser - other"] << [msg, specs]
  elsif msg.include?("assignment")
    categories["Compiler - assignment"] << [msg, specs]
  elsif msg.include?("Missing value") || msg.include?("requires two values")
    categories["Shunting yard"] << [msg, specs]
  elsif msg.include?("undefined reference")
    categories["Link errors"] << [msg, specs]
  elsif msg.include?("undefined method") || msg.include?("NoMethodError") || msg.include?("NilClass")
    categories["Internal errors"] << [msg, specs]
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

  if msg.include?("undefined method") || msg.include?("NoMethodError")
    ease = 4 # Likely needs better error handling/reporting
    priorities << [specs.size * ease, "Fix internal error: #{msg[0...40]}", specs.size, ease]
  elsif msg.include?("Missing value") || msg.include?("requires two values")
    ease = 2 # Medium-hard: shunting yard bugs
    priorities << [specs.size * ease, "Fix shunting yard: #{msg[0...40]}", specs.size, ease]
  elsif msg.include?("undefined reference")
    ease = 5 # Very easy: just add stub classes
    priorities << [specs.size * ease, "Add missing exception/class stubs", specs.size, ease]
  elsif msg.include?("Expected:")
    ease = 3 # Medium: parser fixes
    priorities << [specs.size * ease, "Parser fix: #{msg[0...40]}", specs.size, ease]
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
