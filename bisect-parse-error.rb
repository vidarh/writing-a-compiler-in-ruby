#!/usr/bin/env ruby
# Bisects a file to find the line that introduces a specific parse error

if ARGV.length < 1
  puts "Usage: #{$0} <file_path> <optional flags>"
  exit 1
end

file_path = ARGV[0]
$flags = ARGV[1] || ""


unless File.exist?(file_path)
  puts "Error: File not found: #{file_path}"
  exit 1
end

# Read the full file
lines = File.readlines(file_path)
total_lines = lines.length

puts "File has #{total_lines} lines"

# Try to compile the full file and get the error
def parse_file(file_path)
  output = `ruby -I. ./driver.rb #{file_path} -I. #{$flags} 2>&1 >/dev/null`
  return output
end

full_output = parse_file(file_path)

# Extract the error message
# Match either:
# 1. filename:line:col: message
# 2. (unknown location): message
filename = File.basename(file_path)
error_pattern_with_loc = /^.*#{Regexp.escape(filename)}:(\d+):(\d+): (.+)$/
error_pattern_no_loc = /^\(unknown location\): (.+)$/

error_match = full_output.match(error_pattern_with_loc)
unknown_location = false

unless error_match
  # Try matching unknown location format
  error_match = full_output.match(error_pattern_no_loc)
  unknown_location = true
end

unless error_match
  puts "No parse error found in file!"
  puts "Output:"
  puts full_output
  exit 0
end

if unknown_location
  error_line = nil
  error_col = nil
  error_msg = error_match[1]
  puts "Found error at unknown location:"
  puts "  #{error_msg}"
  puts
  puts "Will bisect to find the line causing this error..."
  puts
else
  error_line = error_match[1].to_i
  error_col = error_match[2].to_i
  error_msg = error_match[3]
  puts "Found error at line #{error_line}, col #{error_col}:"
  puts "  #{error_msg}"
  puts
end

# Now bisect to find where this error first appears
temp_file = "/tmp/bisect_temp_#{Process.pid}.rb"

def has_error?(temp_file, error_msg_pattern)
  output = `ruby -I. ./driver.rb #{temp_file} -I. #{$flags} 2>&1 >/dev/null`
  # Look for the error message pattern anywhere in the output
  puts output
  output.include?(error_msg_pattern)
end

# Binary search to find the first line that causes this error
low = 1
high = total_lines

puts "Bisecting to find first line that causes: #{error_msg}"
puts

while low < high
  mid = (low + high) / 2

  # Write first `mid` lines to temp file
  File.write(temp_file, lines[0...mid].join)

  if has_error?(temp_file, error_msg)
    puts "Lines 1-#{mid}: HAS ERROR"
    high = mid
  else
    puts "Lines 1-#{mid}: Not match"
    low = mid + 1
  end
end

puts
puts "=" * 60
puts "Error first appears when including line #{low}"
puts "=" * 60
puts
puts "Line #{low}:"
puts lines[low - 1]
puts

# Show context
if low > 1
  puts "Previous line (#{low - 1}):"
  puts lines[low - 2]
  puts
end

if low < total_lines
  puts "Next line (#{low + 1}):"
  puts lines[low]
end

# Phase 2: Try to minimize by removing earlier lines
puts
puts "=" * 60
puts "Phase 2: Attempting to minimize by removing earlier lines"
puts "=" * 60
puts

# We now know lines 1..low reproduce the error.
# Try to find a minimal subset by testing if we can skip early lines
# Start from line 1 and binary search for the earliest line we can start from

if low > 1
  min_start = 1
  max_start = low - 1

  puts "Testing if we can start from a later line and still reproduce error..."
  puts

  while min_start < max_start
    mid_start = (min_start + max_start + 1) / 2  # Round up to test removing more

    # Try starting from mid_start..low
    File.write(temp_file, lines[(mid_start-1)...low].join)

    if has_error?(temp_file, error_msg)
      puts "Lines #{mid_start}-#{low}: STILL HAS ERROR (can skip lines 1-#{mid_start-1})"
      min_start = mid_start
    else
      puts "Lines #{mid_start}-#{low}: no error (need earlier lines)"
      max_start = mid_start - 1
    end
  end

  puts
  puts "=" * 60
  puts "Minimal reproducer: lines #{min_start}-#{low}"
  puts "=" * 60
  puts

  if min_start > 1
    puts "Can skip lines 1-#{min_start-1}"
    puts
    puts "Minimal reproducing code:"
    puts "-" * 60
    lines[(min_start-1)...low].each_with_index do |line, idx|
      printf "%3d: %s", min_start + idx, line
    end
    puts "-" * 60
  else
    puts "Cannot reduce further - all lines from 1 to #{low} are needed"
  end
else
  puts "Only one line needed - already minimal"
end

puts
puts "=" * 60
puts "Phase 3: Attempting random removals"
puts "=" * 60
puts

new_lines = lines[(min_start-1)...low]
tries = 10
last_error = new_lines
while tries > 0 && !new_lines.empty?
  modified = new_lines.dup
  l = rand(modified.length)
  puts "#{modified.length} lines left, deleting #{l}"
  modified.delete_at(l)
  File.write(temp_file, modified.join)
  if has_error?(temp_file, error_msg)
    puts "Modified lines STILL HAS ERROR. Reset tries to 10"
    system("cat #{temp_file}")
    last_error = modified.dup
    new_lines = modified
    tries = 10
  else
    tries -= 1
    puts "Modified lines: No match. Tries left: #{tries}"
  end
end

puts
puts "=" * 60
puts "Minimal result"
puts "=" * 60
puts
puts last_error.join

# Clean up
File.delete(temp_file) if File.exist?(temp_file)
