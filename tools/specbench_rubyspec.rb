# tools/specbench_rubyspec.rb
#
# REAL rubyspec benchmark with FULL PHASE-BY-PHASE timing. Runs a fixed set of actual
# rubyspec files and measures every pipeline phase DIRECTLY:
#
#   preprocess -> parse -> transform -> codegen -> link -> run
#
# and records the outcome (PASS / FAIL / CRASH / COMPILE_FAIL / TIMEOUT). This is the
# benchmark that measures what matters for the spec loop. (tools/specbench.rb only times
# the compiler on proxy inputs and runs no spec.)
#
# How each phase is isolated:
#   preprocess : `SPEC_PREPROCESS_ONLY=1 ./run_rubyspec <spec>` -- emits the preprocessed
#                temp spec and stops (opt-in seam in run_rubyspec; default behaviour intact).
#   parse/transform/codegen : tools/bench_compile.rb on the temp (BENCH_TIMING on stderr),
#                emitting out/specrb_<name>.s.
#   link       : gcc assemble+link of the .s (mirrors ./compile's local-toolchain link).
#   run        : timed execution of the linked binary, with outcome classification.
#
# Prefer running on ax52 (uncontended). See docs/COMPILER_WORKFLOW.md.

require 'json'

DIR = File.expand_path("..", __dir__)
Dir.chdir(DIR)

SPEC_SET = (ARGV.empty? ? %w[
  rubyspec/language/and_spec.rb
  rubyspec/language/if_spec.rb
  rubyspec/language/ensure_spec.rb
  rubyspec/language/array_spec.rb
  rubyspec/language/module_spec.rb
] : ARGV)

RUN_TIMEOUT = 30

# --- toolchain link command (mirrors ./compile, local branch) --------------
GLIBC = ENV["GLIBC32_ROOT"] || File.join(DIR, "toolchain", "32root")
LIB32 = File.join(GLIBC, "lib", "i386-linux-gnu")
USR32 = File.join(GLIBC, "usr", "lib32")
unless File.exist?(File.join(LIB32, "libc.so.6")) && File.exist?(File.join(USR32, "crt1.o"))
  abort "Local i386 toolchain missing in #{GLIBC} (see ./compile)."
end
GCC32 = File.dirname(Dir.glob(File.join(GLIBC, "usr", "lib", "gcc", "x86_64-linux-gnu", "*", "32", "crtbegin.o")).first)
USRI386 = File.join(GLIBC, "usr", "lib", "i386-linux-gnu")
DL = File.join(LIB32, "ld-linux.so.2")

def link_cmd(bname)
  flags = ["-m32", "-nostdlib", "-Wl,--dynamic-linker=#{DL}", "-Wl,-rpath,#{LIB32}",
           "-L#{USR32}", "-L#{LIB32}", "-L#{USRI386}", "-L#{GCC32}"].join(" ")
  ["gcc", flags, "-o", "out/#{bname}",
   File.join(USR32, "crt1.o"), File.join(USR32, "crti.o"), File.join(GCC32, "crtbegin.o"),
   "out/#{bname}.s", "out/tgc.o",
   File.join(LIB32, "libc.so.6"), File.join(USR32, "libc_nonshared.a"), File.join(LIB32, "libgcc_s.so.1"),
   File.join(GCC32, "crtend.o"), File.join(USR32, "crtn.o")].join(" ")
end

unless File.exist?("out/tgc.o")
  inc = File.join(GLIBC, "usr", "include", "i386-linux-gnu")
  system("gcc -Wall -isystem #{inc} -c -m32 -o out/tgc.o tgc.c") or abort "tgc build failed"
end

def timed
  t = Time.now
  v = yield
  [(Time.now - t).round(3), v]
end

def strip_ansi(s); s.gsub(/\e\[[0-9;]*[A-Za-z]/, ""); end

results = []
SPEC_SET.each do |spec|
  name  = File.basename(spec, ".rb")
  temp  = "rubyspec_temp_#{name}.rb"
  sfile = "out/specrb_#{name}.s"
  errf  = "out/specrb_#{name}.err"
  bname = "specrb_#{name}"
  STDERR.puts "== #{spec}"
  r = { spec: spec, outcome: nil, passed: nil, failed: nil, skipped: nil,
        preprocess: nil, parse: nil, transform: nil, codegen: nil,
        compile: nil, link: nil, run: nil, total: nil }

  # PHASE 1: preprocess (emit temp, stop)
  r[:preprocess], (_pp, pp_exit) = timed do
    out = `SPEC_PREPROCESS_ONLY=1 ./run_rubyspec #{spec} 2>&1`
    [out, $?.exitstatus]
  end
  unless pp_exit == 0 && File.exist?(temp)
    r[:outcome] = "PREPROCESS_FAIL"; results << r; next
  end

  # PHASE 2: compile (parse/transform/codegen)
  r[:compile], compile_ok = timed do
    system("ruby -I. tools/bench_compile.rb #{temp} -I. -I lib/core >#{sfile} 2>#{errf}")
  end
  if compile_ok && (line = File.exist?(errf) && File.readlines(errf).find { |l| l.start_with?("BENCH_TIMING ") })
    t = JSON.parse(line.sub("BENCH_TIMING ", ""))
    r[:parse], r[:transform], r[:codegen] = t["parse"], t["transform"], t["codegen"]
  end
  unless compile_ok && File.size?(sfile)
    r[:outcome] = "COMPILE_FAIL"
    r[:total] = [r[:preprocess], r[:compile]].compact.sum.round(3)
    results << r; next
  end

  # PHASE 3: link
  r[:link], link_ok = timed { system("#{link_cmd(bname)} 2>#{errf}") }
  unless link_ok && File.exist?("out/#{bname}")
    r[:outcome] = "LINK_FAIL"
    r[:total] = [r[:preprocess], r[:compile], r[:link]].compact.sum.round(3)
    results << r; next
  end

  # PHASE 4: run (timed, with outcome)
  r[:run], (run_out, run_exit) = timed do
    out = `timeout #{RUN_TIMEOUT} out/#{bname} 2>&1`
    [strip_ansi(out), $?.exitstatus]
  end
  m = run_out.match(/(\d+) passed,\s*(\d+) failed,\s*(\d+) skipped/)
  r[:passed], r[:failed], r[:skipped] = m[1].to_i, m[2].to_i, m[3].to_i if m
  r[:outcome] =
    if    run_exit == 124                               then "TIMEOUT"
    elsif run_exit == 139 || run_exit == 136            then "CRASH"
    elsif m.nil?                                        then "CRASH"
    elsif r[:failed] > 0                                then "FAIL"
    else                                                     "PASS"
    end
  r[:total] = [r[:preprocess], r[:compile], r[:link], r[:run]].compact.sum.round(3)
  results << r
end

File.open("docs/specbench_rubyspec.jsonl", "w") { |f| results.each { |x| f.puts JSON.generate(x) } }

def f(x); x.nil? ? "   -  " : ("%6.2f" % x); end
L = []
L << "Real rubyspec benchmark — phase-by-phase, actual rubyspec/language/* files"
L << "Generated by `make specbench-rubyspec` (tools/specbench_rubyspec.rb). Seconds, wall-clock."
L << "Run on ax52 (uncontended) for clean numbers. See docs/COMPILER_WORKFLOW.md."
L << ""
L << ("%-13s %-12s %4s %4s %7s %6s %9s %7s %6s %6s %7s" %
      %w[spec outcome P F prepro parse transform codegen link run total])
L << ("-" * 92)
results.each do |x|
  L << ("%-13s %-12s %4s %4s %7s %6s %9s %7s %6s %6s %7s" % [
    File.basename(x[:spec], ".rb"), x[:outcome],
    (x[:passed] || "-").to_s, (x[:failed] || "-").to_s,
    f(x[:preprocess]), f(x[:parse]), f(x[:transform]), f(x[:codegen]),
    f(x[:link]), f(x[:run]), f(x[:total])])
end
L << ""
L << "Phases measured directly. parse+transform+codegen = compile (lib/core-dominated, ~fixed"
L << "per spec). run = executing the compiled spec (CRASH/TIMEOUT specs burn wall-clock here)."
L << "total = sum of measured phases."
out = L.join("\n")
File.write("docs/specbench_rubyspec_baseline.txt", out + "\n")
puts out
