# tools/specbench.rb
#
# Spec-compile benchmark harness. Measures per-stage wall-clock for the compile
# pipeline over a fixed, representative benchmark set and writes a committed baseline.
# See docs/COMPILER_WORKFLOW.md and docs/plans/SPECBENCH-*.
#
# Stages, per benchmark item:
#   parse / transform / codegen  -- via tools/bench_compile.rb (in-process timing)
#   link                         -- the real gcc assemble+link (mirrors ./compile)
#   run                          -- timed execution of the resulting binary (when meaningful)
#
# The single gcc invocation does assemble (.s -> .o) AND link in one step, so "link"
# covers what would otherwise be gas+ld. Runs under MRI with the local i386 toolchain.
#
# Output:
#   docs/specbench.jsonl        -- one JSON object per benchmark item (machine-readable)
#   docs/specbench_baseline.txt -- human-readable summary table + lib/core floor analysis

require 'json'

DIR = File.expand_path("..", __dir__)
Dir.chdir(DIR)

# --- Fixed benchmark set ---------------------------------------------------
# name:     label in the report
# file:     source to compile
# includes: extra args (include paths) passed to the compiler
# run:      whether timing the resulting binary is meaningful
# floor:    marks the item whose compile time is the lib/core "floor"
BENCH_SET = [
  { name: "tiny",     file: "tools/bench/tiny.rb", includes: ["-I."], run: true,  floor: true  },
  { name: "selftest", file: "test/selftest.rb",    includes: ["-I."], run: true,  floor: false },
  { name: "driver",   file: "driver.rb",           includes: ["-I."], run: false, floor: false },
]

RUN_TIMEOUT = 30
# Each compile is sampled REPS times and the per-stage MINIMUM is kept: min is the
# cleanest estimate of true cost, least perturbed by transient system contention.
REPS = (ENV["SPECBENCH_REPS"] || "3").to_i

# --- Toolchain detection (mirrors ./compile, local branch) -----------------
glibc_root = ENV["GLIBC32_ROOT"] || File.join(DIR, "toolchain", "32root")
lib32 = File.join(glibc_root, "lib", "i386-linux-gnu")
usr32 = File.join(glibc_root, "usr", "lib32")
unless File.exist?(File.join(lib32, "libc.so.6")) && File.exist?(File.join(usr32, "crt1.o"))
  STDERR.puts "Local i386 toolchain not found in #{glibc_root}. specbench needs it (see ./compile)."
  exit(1)
end
crtbegin_glob = Dir.glob(File.join(glibc_root, "usr", "lib", "gcc", "x86_64-linux-gnu", "*", "32", "crtbegin.o"))
if crtbegin_glob.empty?
  STDERR.puts "Cannot find crtbegin.o in #{glibc_root}. Toolchain incomplete."
  exit(1)
end
gcc32 = File.dirname(crtbegin_glob.first)
usr_i386 = File.join(glibc_root, "usr", "lib", "i386-linux-gnu")
dynamic_linker = File.join(lib32, "ld-linux.so.2")
crt1  = File.join(usr32, "crt1.o")
crti  = File.join(usr32, "crti.o")
crtn  = File.join(usr32, "crtn.o")
crtbegin = File.join(gcc32, "crtbegin.o")
crtend   = File.join(gcc32, "crtend.o")

def link_command(bname, parts)
  lib32, usr32, usr_i386, gcc32, dynamic_linker, crt1, crti, crtn, crtbegin, crtend = parts
  flags = [
    "-m32", "-nostdlib",
    "-Wl,--dynamic-linker=#{dynamic_linker}",
    "-Wl,-rpath,#{lib32}",
    "-L#{usr32}", "-L#{lib32}", "-L#{usr_i386}", "-L#{gcc32}"
  ].join(" ")
  [
    "gcc", flags, "-o", "out/#{bname}",
    crt1, crti, crtbegin,
    "out/#{bname}.s", "out/tgc.o",
    File.join(lib32, "libc.so.6"),
    File.join(usr32, "libc_nonshared.a"),
    File.join(lib32, "libgcc_s.so.1"),
    crtend, crtn
  ].join(" ")
end
TC = [lib32, usr32, usr_i386, gcc32, dynamic_linker, crt1, crti, crtn, crtbegin, crtend]

# --- Ensure tgc.o exists (mirrors ./compile) -------------------------------
unless File.exist?("out/tgc.o")
  i386_inc = File.join(glibc_root, "usr", "include", "i386-linux-gnu")
  cflags = File.directory?(i386_inc) ? "-isystem #{i386_inc}" : ""
  unless system("gcc -Wall #{cflags} -c -m32 -o out/tgc.o tgc.c")
    STDERR.puts "Compiling tgc failed."
    exit(1)
  end
end

def timed
  t0 = Time.now
  ok = yield
  [(Time.now - t0).round(4), ok]
end

results = []

BENCH_SET.each do |item|
  bname = "bench_#{item[:name]}"
  sfile = "out/#{bname}.s"
  errfile = "out/#{bname}.bench.err"
  STDERR.puts "== #{item[:name]} (#{item[:file]})"

  # parse/transform/codegen via bench_compile (also produces the .s). Sample REPS
  # times, keep the per-stage minimum.
  args = [item[:file], *item[:includes]].join(" ")
  stages = { "parse" => nil, "transform" => nil, "codegen" => nil, "driver_total" => nil }
  failed = false
  REPS.times do |i|
    cdt, ok = timed do
      system("ruby -I. tools/bench_compile.rb #{args} >#{sfile} 2>#{errfile}")
    end
    unless ok
      STDERR.puts "  compile FAILED:"; STDERR.puts File.read(errfile)
      failed = true; break
    end
    sample = { "driver_total" => cdt }
    line = File.readlines(errfile).find { |l| l.start_with?("BENCH_TIMING ") }
    JSON.parse(line.sub("BENCH_TIMING ", "")).each { |k, v| sample[k] = v } if line
    sample.each do |k, v|
      next if v.nil?
      stages[k] = stages[k].nil? ? v : [stages[k], v].min
    end
    STDERR.puts "  rep #{i + 1}/#{REPS}: #{cdt}s"
  end
  if failed
    results << { name: item[:name], file: item[:file], ok: false, stage: "compile" }
    next
  end

  # link (gcc assemble + link). First link in a process pays toolchain/FS warmup
  # (cold libc.so.6 etc.), so link twice and keep the warm (min) time.
  lcmd = link_command(bname, TC)
  l1, lok = timed { system("#{lcmd} 2>#{errfile}") }
  unless lok
    STDERR.puts "  link FAILED:"; STDERR.puts File.read(errfile)
    results << { name: item[:name], file: item[:file], ok: false, stage: "link", stages: stages, link: l1 }
    next
  end
  l2, _ = timed { system("#{lcmd} 2>#{errfile}") }
  ltime = [l1, l2].min

  # run (timed, when meaningful)
  rtime = nil
  if item[:run]
    rtime, _ = timed { system("timeout #{RUN_TIMEOUT} out/#{bname} >/dev/null 2>&1") }
  end

  asm_lines = File.foreach(sfile).count
  results << {
    name: item[:name], file: item[:file], ok: true,
    parse: stages["parse"], transform: stages["transform"], codegen: stages["codegen"],
    compile_total: stages["driver_total"], link: ltime, run: rtime,
    asm_lines: asm_lines, floor: item[:floor]
  }
end

# --- Write machine-readable jsonl ------------------------------------------
File.open("docs/specbench.jsonl", "w") do |f|
  results.each { |r| f.puts JSON.generate(r) }
end

# --- Write human summary ---------------------------------------------------
floor = results.find { |r| r[:ok] && r[:floor] }
def fmt(x); x.nil? ? "  -  " : ("%6.2f" % x); end

lines = []
lines << "Spec-compile benchmark baseline"
lines << "Generated by `make specbench` (tools/specbench.rb). Times in seconds, wall-clock."
lines << "Per-stage values are the MIN of #{REPS} samples (SPECBENCH_REPS). link/run are warm."
lines << "link = gcc assemble+link (single step). See docs/COMPILER_WORKFLOW.md."
lines << ""
lines << ("%-10s %7s %9s %8s %9s %7s %7s %10s" %
          ["name", "parse", "transform", "codegen", "compile", "link", "run", "asm_lines"])
lines << ("-" * 72)
results.each do |r|
  if r[:ok]
    lines << ("%-10s %7s %9s %8s %9s %7s %7s %10d" %
              [r[:name], fmt(r[:parse]), fmt(r[:transform]), fmt(r[:codegen]),
               fmt(r[:compile_total]), fmt(r[:link]), fmt(r[:run]), r[:asm_lines]])
  else
    lines << ("%-10s  FAILED at %s" % [r[:name], r[:stage]])
  end
end
lines << ""
if floor
  lines << "lib/core floor (from '#{floor[:name]}'): compile #{fmt(floor[:compile_total])}s, #{floor[:asm_lines]} asm lines."
  lines << "This fixed cost is paid by EVERY compile (parser.rb auto-requires core/core.rb)."
  results.each do |r|
    next unless r[:ok] && !r[:floor] && r[:compile_total] && r[:compile_total] > 0
    pct = (100.0 * floor[:compile_total] / r[:compile_total]).round(1)
    lalines = (100.0 * floor[:asm_lines] / r[:asm_lines]).round(1)
    lines << "  #{r[:name]}: floor is #{pct}% of its compile time, #{lalines}% of its asm lines."
  end
end

summary = lines.join("\n")
File.write("docs/specbench_baseline.txt", summary + "\n")
puts summary
