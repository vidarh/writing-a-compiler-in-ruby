# tools/bench_compile.rb
#
# Instrumented mirror of driver.rb used by the spec-speedup benchmark harness
# (see docs/SPEC_SPEEDUP_WORKFLOW.md / docs/plans/SPECBENCH-*).
#
# It compiles a file exactly like driver.rb but times the three in-process stages
# and emits a one-line JSON timing record to STDERR:
#
#     BENCH_TIMING {"parse":1.23,"transform":0.45,"codegen":1.99,"driver_total":3.70}
#
# The assembly is written to STDOUT, identical to driver.rb, so callers redirect
# stdout to the .s file and read the timing line from stderr.
#
# This deliberately duplicates driver.rb's control flow; if driver.rb's stage
# structure changes, update this in lockstep. It lives in tools/ (not compiled by
# the self-host), so it may freely use Time.now and JSON under MRI.

require 'compilererror'
require 'compiler'
require 'json'

def now
  Time.now
end

norequire   = ARGV.include?("--norequire")
trace       = ARGV.include?("--trace")
stackfence  = ARGV.include?("--stackfence")
transform   = !ARGV.include?("--notransform")
nostabs     = ARGV.include?("--nostabs")

OpPrec::TreeOutput.dont_rewrite if ARGV.include?("--dont-rewrite")

input_source = STDIN
include_paths = []

while arg = ARGV.shift
  if arg[0..1] == "-I"
    path = (arg == "-I") ? ARGV.shift : arg[2..-1]
    include_paths << path
  elsif arg == "-g"
  elsif arg[0..1] == "--"
  elsif File.exist?(arg)
    input_source = File.open(arg, "r")
  else
    STDERR.puts "No such file or argument: '#{arg}'"
    exit(1)
  end
end

timing = {}
t0 = now

s = Scanner.new(input_source)
prog = nil

begin
  parser = Parser.new(s, {:norequire => norequire, :include_paths => include_paths})
  prog = parser.parse
rescue CompilerError => e
  STDERR.puts e.message
  exit(1)
end
t_parse = now
timing[:parse] = (t_parse - t0).round(4)

if prog
  begin
    e = Emitter.new
    e.debug == nil if nostabs

    c = Compiler.new(e)
    c.trace = true if trace
    c.stackfence = true if stackfence

    t_pre0 = now
    c.preprocess(prog) if transform
    t_pre1 = now
    timing[:transform] = (t_pre1 - t_pre0).round(4)

    c.compile(prog)
    t_cg = now
    timing[:codegen] = (t_cg - t_pre1).round(4)
  rescue CompilerError => e
    STDERR.puts e.message
    exit(1)
  end
else
  timing[:transform] = 0.0
  timing[:codegen]   = 0.0
end

timing[:driver_total] = (now - t0).round(4)
STDERR.puts "BENCH_TIMING #{JSON.generate(timing)}"
exit(0)
