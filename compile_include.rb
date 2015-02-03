
class Compiler
  def compile_include(scope, incl)
    STDERR.puts "FIXME: include #{incl.inspect} -- not implemented"
    Value.new([:subexpr])
  end
end
