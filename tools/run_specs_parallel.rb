# tools/run_specs_parallel.rb
#
# Parallel rubyspec runner. Runs independent spec files concurrently across a worker pool
# (default: nproc), each through the REAL per-spec `run_rubyspec` path (preprocess ->
# compile -> link -> run). Aggregates outcomes and writes machine-readable results.
#
# Each spec is an independent ~2-3.5s job, so this is much faster than sequential
# run_rubyspec. Intended to run on ax52 (uncontended; 16 cores).
#
# Worker-count tuning (ax52, 16 cores, rubyspec/language, 10s timeout):
#   j=4 75.4s  j=8 47.0s  j=12 40.9s  j=16 38.5s  j=20 38.1s  j=24 38.3s  j=32 39.4s
# Knee at ~12-16; past nproc it is flat-to-worse (memory-bandwidth/tail-bound, not
# core-bound). Default = nproc is optimal. Further speedup needs lower per-spec compile
# cost (COREMARSHAL) or fixing hanging specs, not more workers.
#
# Usage:
#   ruby -I. tools/run_specs_parallel.rb <dir-or-spec> [-j N] [-o results.jsonl]
#   ruby -I. tools/run_specs_parallel.rb rubyspec/language -j 16
#
# Notes / current limits:
# - Per-spec temp/binary names are keyed on the spec BASENAME (run_rubyspec single-file
#   mode), so a set with duplicate basenames across dirs could collide. A single directory
#   like rubyspec/language has unique basenames. Flagged for later (namespacing).
# - Classification mirrors run_rubyspec: COMPILE_FAIL / TIMEOUT / CRASH / FAIL / PASS.

require 'json'
require 'thread'

DIR = File.expand_path("..", __dir__)
Dir.chdir(DIR)

# --- args ---
target = nil
jobs = nil
outfile = "docs/spec_parallel_results.jsonl"
spec_timeout = 10   # per-spec RUN timeout (s); hanging specs are killed here, not at 30s
args = ARGV.dup
while (a = args.shift)
  case a
  when "-j" then jobs = args.shift.to_i
  when "-o" then outfile = args.shift
  when "-t" then spec_timeout = args.shift.to_i
  else target = a
  end
end
abort "usage: run_specs_parallel.rb <dir-or-spec> [-j N] [-o results.jsonl]" unless target
jobs ||= (`nproc`.to_i rescue 4)
jobs = 4 if jobs < 1

specs =
  if File.directory?(target)
    Dir.glob("#{target}/**/*_spec.rb").reject { |f| f.include?("/shared/") || f.include?("/fixtures/") }.sort
  else
    [target]
  end
abort "no spec files under #{target}" if specs.empty?

# --- pre-build out/tgc.o once (avoid a build race across workers) ---
unless File.exist?("out/tgc.o")
  glibc = ENV["GLIBC32_ROOT"] || File.join(DIR, "toolchain", "32root")
  inc = File.join(glibc, "usr", "include", "i386-linux-gnu")
  cflags = File.directory?(inc) ? "-isystem #{inc}" : ""
  system("gcc -Wall #{cflags} -c -m32 -o out/tgc.o tgc.c") or abort "tgc build failed"
end

def strip_ansi(s); s.gsub(/\e\[[0-9;]*[A-Za-z]/, ""); end

def classify(out, exit_code)
  clean = strip_ansi(out)
  m = clean.match(/(\d+) passed,\s*(\d+) failed,\s*(\d+) skipped/)
  if m
    p, f, s = m[1].to_i, m[2].to_i, m[3].to_i
  else
    # No summary (crash/timeout before completion): recover partial counts from the
    # last per-test progress marker "[P:n F:n S:n]", as run_rubyspec itself does.
    last = clean.scan(/\[P:(\d+) F:(\d+) S:(\d+)\]/).last
    p, f, s = last ? last.map(&:to_i) : [nil, nil, nil]
  end
  outcome =
    if    exit_code == 3                              then "COMPILE_FAIL"
    elsif exit_code == 124                            then "TIMEOUT"
    elsif exit_code == 2 || exit_code == 139 || exit_code == 136 then "CRASH"
    elsif m.nil?                                      then "CRASH"
    elsif f > 0                                       then "FAIL"
    else                                                  "PASS"
    end
  [outcome, p, f, s]
end

queue = Queue.new
specs.each { |s| queue << s }
results = []
mutex = Mutex.new
done = 0
total = specs.size
t0 = Time.now

workers = jobs.times.map do
  Thread.new do
    loop do
      spec = (queue.pop(true) rescue nil)
      break unless spec
      out = `SPEC_TIMEOUT=#{spec_timeout} ./run_rubyspec #{spec} 2>&1`
      ec = $?.exitstatus
      outcome, p, f, s = classify(out, ec)
      mutex.synchronize do
        done += 1
        results << { spec: spec, outcome: outcome, passed: p, failed: f, skipped: s }
        printf("[%3d/%3d] %-12s %s (P:%s F:%s S:%s)\n",
               done, total, outcome, spec.sub("rubyspec/", ""),
               p || "-", f || "-", s || "-")
      end
    end
  end
end
workers.each(&:join)
elapsed = Time.now - t0

# cleanup litter from run_rubyspec single-file mode
Dir.glob("rubyspec_temp_*.rb").each { |f| File.delete(f) rescue nil }

results.sort_by! { |r| r[:spec] }
File.open(outfile, "w") { |f| results.each { |r| f.puts JSON.generate(r) } }

by = Hash.new(0)
tp = tf = ts = 0
results.each do |r|
  by[r[:outcome]] += 1
  tp += r[:passed] || 0; tf += r[:failed] || 0; ts += r[:skipped] || 0
end

puts
puts "=" * 56
puts "Parallel rubyspec run — #{target}  (#{jobs} workers, #{spec_timeout}s spec timeout)"
puts "Files: #{total}   wall-clock: #{elapsed.round(1)}s   (#{(elapsed / total).round(2)}s/spec avg)"
puts "  PASS:%-4d FAIL:%-4d CRASH:%-4d COMPILE_FAIL:%-3d TIMEOUT:%-3d" %
     [by["PASS"], by["FAIL"], by["CRASH"], by["COMPILE_FAIL"], by["TIMEOUT"]]
puts "  tests: #{tp} passed, #{tf} failed, #{ts} skipped"
puts "results -> #{outfile}"
