# tools/crash_trace.rb
#
# Cluster crashing specs by the instruction they crash on. (classify_failures.rb only parses
# stdout, so no-output crashers are left uncharacterized.)
#
# Per crasher: preprocess to a temp, compile via ./compile with -g (so gdb resolves the crash
# to a .s line), run under gdb, read that .s line. The crash is typically `call *N(%reg)` — a
# virtual dispatch through a null vtable slot; the offset N is GLOBAL, so it clusters specs by
# the missing method across the whole suite. Specs that don't deterministically segfault under
# gdb, or fail to compile with -g, are bucketed honestly.
#
# Usage: ruby -I. tools/crash_trace.rb [spec ...]   (default: all CRASH in docs/spec_status.jsonl)
# Writes docs/crash_clusters.txt.

require "json"
DIR = File.expand_path("..", __dir__)
Dir.chdir(DIR)

specs = if ARGV.empty?
  File.readlines("docs/spec_status.jsonl").map { |l| JSON.parse(l) }
    .select { |r| r["outcome"] == "CRASH" }.map { |r| r["spec"] }
else
  ARGV
end

# Read the .s source line of the innermost frame gdb could resolve (frame #0 is often the
# null target `0x0 in ??`; the first `at <file>.s:N` is the real crash site).
def crash_site(bin, sfile)
  bt = `gdb -batch -ex 'set pagination off' -ex run -ex 'bt 16' #{bin} </dev/null 2>&1`
  return [:nocrash, nil] unless bt =~ /SIG(SEGV|ABRT|BUS|ILL)|signal/
  line = bt[%r{ at (?:\S+/)?\S+\.s:(\d+)}, 1]
  return [:noline, nil] unless line
  src = (File.readlines(sfile)[line.to_i - 1] || "").strip
  [:crash, src]
end

def signature(src)
  return "<empty>" if src.nil? || src.empty?
  # virtual dispatch through a vtable slot: `call *12(%eax)` — offset is the global method slot
  if src =~ /\bcall\s+\*(0x[0-9a-f]+|\d+)\(%/
    return "vtable-call slot +#{$1}"
  elsif src =~ /\bcall\s+\*%/
    return "indirect-call (computed)"
  end
  op, rest = src.split(/\s+/, 2)
  "#{op} #{rest}".strip
end

groups = Hash.new { |h, k| h[k] = [] }
specs.each_with_index do |spec, i|
  name = spec.sub(/\.rb$/, "").gsub(%r{[/.]}, "_")
  base = File.basename(spec, ".rb")
  STDERR.puts "[#{i + 1}/#{specs.size}] #{base}"
  system("SPEC_PREPROCESS_ONLY=1 ./run_rubyspec #{spec} >/dev/null 2>&1")
  temp = "tmp/rubyspec_temp_#{name}.rb"
  unless File.exist?(temp)
    groups["preprocess-fail"] << base; next
  end
  bin = "out/rubyspec_temp_#{name}"
  sfile = "#{bin}.s"
  File.delete(bin) if File.exist?(bin)
  unless system("./compile #{temp} -I. -I lib/core -g >/dev/null 2>&1") && File.exist?(bin)
    groups["compile-fail"] << base; next
  end
  kind, src = crash_site(bin, sfile)
  sig = case kind
        when :nocrash then "no-segfault-under-gdb (flaky/exit-code)"
        when :noline  then "crash, unresolved frame"
        else "crash @ #{signature(src)}"
        end
  groups[sig] << base
end

ranked = groups.sort_by { |_s, sp| -sp.size }
out = ["Crash clusters by crashing instruction (gdb, ranked by spec count)", ""]
ranked.each do |s, sp|
  out << ("%3d  %s" % [sp.size, s])
  out << "     #{sp.sort.first(20).join(", ")}#{sp.size > 20 ? " ..." : ""}"
end
text = out.join("\n")
File.write("docs/crash_clusters.txt", text + "\n")
puts text
