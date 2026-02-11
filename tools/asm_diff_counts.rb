# Compare opcode frequencies between two assembler files.
# Usage: ruby tools/asm_diff_counts.rb old.s new.s

old, newf = ARGV
abort "Usage: ruby tools/asm_diff_counts.rb old.s new.s" unless old && newf

def count_ops(path)
  counts = Hash.new(0)
  total = 0
  File.foreach(path) do |line|
    line = line.strip
    next if line.empty?
    next if line.start_with?('#', '.')
    next if line.end_with?(':')
    if line =~ /^([a-z.]+)\b/
      op = Regexp.last_match(1)
      counts[op] += 1
      total += 1
    end
  end
  [total, counts]
end

old_total, old_counts = count_ops(old)
new_total, new_counts = count_ops(newf)

ops = (old_counts.keys + new_counts.keys).uniq
deltas = ops.map do |op|
  [op, (new_counts[op] || 0) - (old_counts[op] || 0), old_counts[op] || 0, new_counts[op] || 0]
end

puts "Old total: #{old_total}"
puts "New total: #{new_total}"
puts "Delta: #{new_total - old_total}"
puts
puts "Top opcode deltas:"
deltas.sort_by { |_, delta, _, _| -delta.abs }.first(25).each do |op, delta, o, n|
  next if delta.zero?
  puts "%8d  %-12s (old: %-6d new: %-6d)" % [delta, op, o, n]
end
