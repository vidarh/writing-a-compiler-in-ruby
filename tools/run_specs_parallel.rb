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
outfile = nil
spec_timeout = 10   # per-spec RUN timeout (s); hanging specs are killed here, not at 30s
targets = []
args = ARGV.dup
while (a = args.shift)
  case a
  when "-j" then jobs = args.shift.to_i
  when "-o" then outfile = args.shift
  when "-t" then spec_timeout = args.shift.to_i
  else targets << a
  end
end
abort "usage: run_specs_parallel.rb <dir-or-spec>... [-j N] [-t SECS] [-o out.jsonl]" if targets.empty?
jobs ||= (`nproc`.to_i rescue 4)
jobs = 4 if jobs < 1

# One diffable summary across all targets. Default outputs (overridable via -o):
outfile ||= "docs/spec_status.jsonl"
mdfile = outfile.sub(/\.jsonl$/, "") + ".md"
require "fileutils"; FileUtils.mkdir_p(File.dirname(outfile))

specs = targets.flat_map do |t|
  if File.directory?(t)
    Dir.glob("#{t}/**/*_spec.rb").reject { |f| f.include?("/shared/") || f.include?("/fixtures/") }
  else
    [t]
  end
end.uniq.sort
abort "no spec files under: #{targets.join(", ")}" if specs.empty?

# --- pre-build out/tgc.o once (avoid a build race across workers) ---
unless File.exist?("out/tgc.o")
  glibc = ENV["GLIBC32_ROOT"] || File.join(DIR, "toolchain", "32root")
  inc = File.join(glibc, "usr", "include", "i386-linux-gnu")
  cflags = File.directory?(inc) ? "-isystem #{inc}" : ""
  system("gcc -Wall #{cflags} -c -m32 -o out/tgc.o tgc.c") or abort "tgc build failed"
end

# --- COREMARSHAL: cache lib/core's parsed AST ONCE, then reuse it for every per-spec compile. Each
# compile otherwise re-parses all of lib/core (~30-50% of a spec's compile time). We generate the cache
# here (single process, no race) with COREMARSHAL_DUMP, then export COREMARSHAL_AST so every worker's
# `./run_rubyspec` -> `./compile` -> driver.rb reads it (backticks inherit ENV). The compiler validates
# the cache's checksum against the live lib/core on each read, so a stale cache is NEVER used (it falls
# back to a full parse) -- and we regenerate fresh here anyway. Output is byte-identical with/without.
# Default ON; set COREMARSHAL=0 to disable. Same host writes and reads, so the key always matches.
unless ENV["COREMARSHAL"] == "0"
  core_cache = "out/core.ast"
  File.delete(core_cache) if File.exist?(core_cache)
  system("echo nil | COREMARSHAL_DUMP=#{core_cache} ruby -I. #{DIR}/driver.rb -I. -I lib/core > /dev/null 2>&1")
  if File.exist?(core_cache) && File.size(core_cache) > 0
    ENV["COREMARSHAL_AST"] = core_cache
    puts "COREMARSHAL: reusing cached lib/core AST (#{core_cache}, #{File.size(core_cache)} bytes) for all compiles"
  else
    puts "COREMARSHAL: cache generation failed -- compiling without the cache"
  end
end

# scrub: spec output can contain invalid UTF-8 bytes (binary garbage from a crash),
# which would make gsub raise ArgumentError and kill the worker.
def strip_ansi(s); s.scrub("").gsub(/\e\[[0-9;]*[A-Za-z]/, ""); end

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

# Save the combined stdout+stderr of every CRASH-classified spec to tmp/crash_logs/, keyed on the
# spec path (collision-safe). These flaky crashers only fault under the full parallel sweep, so this
# is the only place their crash-time output (e.g. the __alloc calloc-failure diagnostic, or a libc
# abort message) can be captured for post-mortem. Cheap: only written for the handful that crash.
crash_dir = "tmp/crash_logs"
Dir.mkdir("tmp") unless Dir.exist?("tmp")
Dir.mkdir(crash_dir) unless Dir.exist?(crash_dir)

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
      outcome, p, f, s = "ERROR", nil, nil, nil
      begin
        out = `SPEC_TIMEOUT=#{spec_timeout} ./run_rubyspec #{spec} 2>&1`
        outcome, p, f, s = classify(out, $?.exitstatus)
        if outcome == "CRASH"
          logname = spec.sub(/\.rb$/, "").gsub(%r{[/.]}, "_")
          File.write("#{crash_dir}/#{logname}.log", out) rescue nil
        end
      rescue => e
        # one spec failing to process must never abort the whole run
        outcome = "ERROR"
        $stderr.puts "  [error processing #{spec}: #{e.class}: #{e.message}]"
      end
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

# cleanup litter from run_rubyspec single-file mode (temps in tmp/, binaries in out/)
Dir.glob("tmp/rubyspec_temp_*.rb").each { |f| File.delete(f) rescue nil }

results.sort_by! { |r| r[:spec] }
File.open(outfile, "w") { |f| results.each { |r| f.puts JSON.generate(r) } }

ORDER = %w[PASS FAIL CRASH COMPILE_FAIL TIMEOUT ERROR]
def tally(rs)
  by = Hash.new(0); tp = tf = ts = 0
  rs.each { |r| by[r[:outcome]] += 1; tp += r[:passed] || 0; tf += r[:failed] || 0; ts += r[:skipped] || 0 }
  [by, tp, tf, ts]
end
by, tp, tf, ts = tally(results)
def counts_line(by); ORDER.map { |o| "#{o} #{by[o]}" }.join("  "); end

# category = path under rubyspec/ (e.g. "language", "core/integer")
results.each { |r| r[:cat] = File.dirname(r[:spec]).sub(%r{^rubyspec/}, "") }
cats = results.group_by { |r| r[:cat] }.sort_by { |c, _| c }

# --- human-readable, git-diffable summary (one file) ---
md = []
md << "# Rubyspec status"
md << ""
md << "Single diffable summary, generated by `tools/run_specs_parallel.rb` (`make specs-parallel`)."
md << "Outcomes per spec; commit to track burndown progress over time."
md << ""
md << "**Totals (#{total} files):** #{counts_line(by)}"
md << "**Tests:** #{tp} passed, #{tf} failed, #{ts} skipped"
md << ""
md << "## By category"
md << ""
md << "| category | files | #{ORDER.join(" | ")} |"
md << "|#{"---|" * (ORDER.size + 2)}"
cats.each do |cat, rs|
  cby, = tally(rs)
  md << "| #{cat} | #{rs.size} | #{ORDER.map { |o| cby[o] }.join(" | ")} |"
end
md << ""
md << "## Specs by outcome"
ORDER.each do |o|
  specs_o = results.select { |r| r[:outcome] == o }.sort_by { |r| r[:spec] }
  next if specs_o.empty?
  md << ""
  md << "### #{o} (#{specs_o.size})"
  specs_o.each do |r|
    name = r[:spec].sub(%r{^rubyspec/}, "").sub(/\.rb$/, "")
    cnt = r[:passed] ? " — P:#{r[:passed]} F:#{r[:failed]} S:#{r[:skipped]}" : ""
    md << "- #{name}#{cnt}"
  end
end
File.write(mdfile, md.join("\n") + "\n")

puts
puts "=" * 56
puts "Parallel rubyspec run — #{targets.join(", ")}  (#{jobs} workers, #{spec_timeout}s timeout)"
puts "Files: #{total}   wall-clock: #{elapsed.round(1)}s   (#{(elapsed / total).round(2)}s/spec avg)"
puts "  #{counts_line(by)}"
puts "  tests: #{tp} passed, #{tf} failed, #{ts} skipped"
puts "results -> #{outfile}  +  #{mdfile}"
