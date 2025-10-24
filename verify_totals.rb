#!/usr/bin/env ruby

# Read spec_failures_new.txt and verify the totals

passed_sum = 0
failed_sum = 0
skipped_sum = 0
total_sum = 0
specs_with_counts = 0
specs_without_counts = 0

File.read("spec_failures_new.txt").each_line do |line|
  # Look for lines like: [PASS] file.rb (P:2 F:0 S:0 T:2)
  if line =~ /\[(?:PASS|FAIL|SEGFAULT|COMPILE FAIL)\]\s+(\S+)/
    spec_file = $1
    if line =~ /\(P:(\d+) F:(\d+) S:(\d+) T:(\d+)\)/
      p = $1.to_i
      f = $2.to_i
      s = $3.to_i
      t = $4.to_i

      passed_sum += p
      failed_sum += f
      skipped_sum += s
      total_sum += t
      specs_with_counts += 1

      # Verify that the total matches the sum
      if p + f + s != t
        puts "ERROR in line: #{line}"
        puts "  P:#{p} + F:#{f} + S:#{s} = #{p+f+s} but T:#{t}"
      end
    else
      # No counts for this spec
      specs_without_counts += 1
      puts "No counts for: #{spec_file}"
    end
  end
end

puts
puts "Specs with counts: #{specs_with_counts}"
puts "Specs without counts: #{specs_without_counts}"
puts
puts "Calculated totals (from specs with counts):"
puts "  Passed: #{passed_sum}"
puts "  Failed: #{failed_sum}"
puts "  Skipped: #{skipped_sum}"
puts "  Total: #{total_sum}"
puts

# Now read the summary at the bottom
content = File.read("spec_failures_new.txt")
if content =~ /Individual Test Cases:\s+Total tests: (\d+)\s+Passed: (\d+)\s+Failed: (\d+)\s+Skipped: (\d+)/m
  reported_total = $1.to_i
  reported_passed = $2.to_i
  reported_failed = $3.to_i
  reported_skipped = $4.to_i

  puts "Reported totals:"
  puts "  Passed: #{reported_passed}"
  puts "  Failed: #{reported_failed}"
  puts "  Skipped: #{reported_skipped}"
  puts "  Total: #{reported_total}"
  puts

  if passed_sum == reported_passed && failed_sum == reported_failed &&
     skipped_sum == reported_skipped && total_sum == reported_total
    puts "✓ Totals match!"
  else
    puts "✗ MISMATCH:"
    puts "  Passed: #{passed_sum} calculated vs #{reported_passed} reported (diff: #{passed_sum - reported_passed})"
    puts "  Failed: #{failed_sum} calculated vs #{reported_failed} reported (diff: #{failed_sum - reported_failed})"
    puts "  Skipped: #{skipped_sum} calculated vs #{reported_skipped} reported (diff: #{skipped_sum - reported_skipped})"
    puts "  Total: #{total_sum} calculated vs #{reported_total} reported (diff: #{total_sum - reported_total})"
  end
else
  puts "Could not find summary in spec_failures_new.txt"
end
