# Simple asm n-gram counter for generated .s files.
# Usage: ruby tools/asm_ngram.rb out/*.s --n 3 --limit 30

require 'optparse'

options = { n: 3, limit: 20 }

OptionParser.new do |opts|
  opts.on("--n N", Integer, "n-gram size (default #{options[:n]})") { |v| options[:n] = v }
  opts.on("--limit N", Integer, "how many results to show (default #{options[:limit]})") { |v| options[:limit] = v }
  opts.on("--min-count N", Integer, "only show n-grams with at least N occurrences") { |v| options[:min] = v }
end.parse!

files = ARGV
abort "Pass one or more .s files" if files.empty?

def parse_instructions(path)
  instrs = []
  File.foreach(path) do |line|
    line = line.strip
    next if line.empty?
    next if line.start_with?('#', '.')
    next if line.end_with?(':') # label
    if line =~ /^\s*([a-z.]+)\s+(.*)$/
      op = Regexp.last_match(1)
      args = Regexp.last_match(2).split(/\s*,\s*/)
      instrs << [op, *args]
    end
  end
  instrs
end

ngrams = Hash.new(0)
total = 0

files.each do |path|
  ins = parse_instructions(path)
  ins.each_cons(options[:n]) do |window|
    key = window.map { |i| i.join(' ') }.join(' | ')
    ngrams[key] += 1
    total += 1
  end
end

min = options[:min] || 1
sorted = ngrams.select { |_, c| c >= min }.sort_by { |_, c| -c }

puts "Total #{options[:n]}-grams: #{total}, unique: #{ngrams.size}"
puts
sorted.first(options[:limit]).each do |k, c|
  puts "%8d  %s" % [c, k]
end
