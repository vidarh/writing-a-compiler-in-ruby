# tools/classify_failures.rb
#
# Lean failure-signature extractor for burndown. For each non-PASS spec it re-runs the
# already-built binary (out/rubyspec_temp_<name>) under a PTY (`script`, so output survives
# a segfault — single-file run_rubyspec block-buffers and loses it), and extracts a crash
# signature:
#   - "exception: <msg>"  for a clean Unhandled-exception (a compiler/runtime bug), normalized
#   - "warn: <...>"        for a Method-resolution WARNING
#   - "segfault @ <ctx>"   the last describe/it context printed before a silent segfault
#   - "compile-fail"       no binary (compilation failed)
# Groups by signature and ranks, so same-root-cause failures cluster.
#
# Run on ax52 (binaries present from a prior `make specs-parallel`). Reads the results
# JSONL; writes docs/failure_signatures.txt.
#
# Usage: ruby -I. tools/classify_failures.rb [results.jsonl]

require 'json'
DIR = File.expand_path("..", __dir__)
Dir.chdir(DIR)

infile = ARGV[0] || "docs/spec_parallel_results.jsonl"
RUN_TIMEOUT = 10

def strip_ansi(s); s.gsub(/\e\[[0-9;]*[A-Za-z]/, ""); end

def signature(name, outcome)
  return "compile-fail" if outcome == "COMPILE_FAIL"
  bin = "out/rubyspec_temp_#{name}"
  return "no-binary (#{outcome})" unless File.executable?(bin)
  tmp = "/tmp/cf_#{name}_#{Process.pid}"
  system("timeout #{RUN_TIMEOUT} script -q -c './#{bin}' #{tmp} </dev/null >/dev/null 2>&1")
  raw = File.exist?(tmp) ? File.read(tmp) : ""
  File.delete(tmp) rescue nil
  clean = strip_ansi(raw)

  if (m = clean.match(/Unhandled exception: (.+)/))
    msg = m[1].strip
    msg = msg.gsub(/0x[0-9a-fA-F]+/, "").gsub(/#<([A-Za-z0-9_]+)[^>]*>/, '<\1>').strip
    return "exception: #{msg}"
  end
  if (m = clean.match(/WARNING:\s+Method:\s*'([^']+)'/))
    return "warn-method: #{m[1]}"
  end
  # silent segfault: localize to the last meaningful context line printed
  ctx = clean.lines.map(&:strip).reject { |l| l.empty? || l.start_with?("Script ") || l.start_with?("DEBUG") }
  last = ctx.last
  if last && last =~ /\[P:\d+ F:\d+ S:\d+\]/
    # crashed on the *next* (unprinted) example after this one; name the describe block
    desc = ctx.reverse.find { |l| l !~ /^[✓✗]/ && l !~ /\[P:/ }
    return "segfault after: #{(desc || last)[0, 60]}"
  end
  "segfault @ #{(last || "<no output>")[0, 60]}"
end

results = File.readlines(infile).map { |l| JSON.parse(l) }
failing = results.reject { |r| r["outcome"] == "PASS" }

groups = Hash.new { |h, k| h[k] = [] }
failing.each do |r|
  name = File.basename(r["spec"], ".rb")
  STDERR.puts "classify #{name} (#{r["outcome"]})"
  sig = signature(name, r["outcome"])
  groups[sig] << name
end

ranked = groups.sort_by { |_sig, specs| -specs.size }
out = []
out << "Failure signatures — ranked by spec count (burndown targets)"
out << "From #{infile}. One fix per signature ideally clears all its specs."
out << ""
ranked.each do |sig, specs|
  out << ("%3d  %s" % [specs.size, sig])
  out << "     #{specs.sort.join(", ")}"
end
text = out.join("\n")
File.write("docs/failure_signatures.txt", text + "\n")
puts text
