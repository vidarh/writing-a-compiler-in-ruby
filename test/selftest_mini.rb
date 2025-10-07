require 'set'
require 'scanner'
require 'ast'
require 'extensions'

include AST

def rewrite_let_env_stub(exp)
  exp.depth_first(:defm) do |e|
    args   = Set[*e[2].collect{|a| a.kind_of?(Array) ? a[0] : a}]

    ac = 0
    STDERR.puts "DEBUG: Before e[2].each"
    e[2].each{|a| ac += 1 if ! a.kind_of?(Array)}
    STDERR.puts "DEBUG: After e[2].each"
    STDERR.puts "DEBUG: args.class="
    STDERR.puts args.class

    :skip
  end
end

def test_stub
  prog = E[:do, E[:defm, :foo, [], [E[:call, :yield]]]]
  rewrite_let_env_stub(prog)
  puts "ok"
end

test_stub
