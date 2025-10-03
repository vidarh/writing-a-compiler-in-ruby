#!/usr/bin/env ruby
$: << File.dirname(__FILE__)
require 'compiler'
require 'stringio'
require 'pp'

code = <<-RUBY
def test
  [[1]].each do |arr|
    arr.each {|x| puts arr.length }
  end
end
RUBY

io = StringIO.new(code)
scanner = Scanner.new(io)
parser = Parser.new(scanner, {:norequire => true})
ast = parser.parse

puts "=== ORIGINAL AST ==="
pp ast

puts "\n=== Now tracing find_vars by inserting debug into transform.rb ==="

# Let's manually trace through what should happen
# Read the actual find_vars code and add instrumentation
require_relative 'transform'

# Save original source
orig_transform = File.read('transform.rb')

# Add debug output right at line 242-248
debug_patch = orig_transform.sub(
  /(\s+elsif n\[0\] == :lambda \|\| n\[0\] == :proc\n\s+vars, env2= find_vars\(n\[2\], scopes \+ \[Set\.new\],env, freq, true\))/,
  "\\1\n          puts \"DEBUG: Lambda/proc params=\#{n[1].inspect}, env2 before cleanup=\#{env2.inspect}\""
)

debug_patch = debug_patch.sub(
  /(\s+env2  -= n\[1\] if n\[1\])/,
  "          puts \"DEBUG: Removing params from env2\"\n\\1\n          puts \"DEBUG: env2 after removal=\#{env2.inspect}\""
)

# Write debug version
File.write('transform_debug.rb', debug_patch)

# Load it
load 'transform_debug.rb'

compiler = Compiler.new
vars, env = compiler.find_vars(ast, [Set.new], Set.new, Hash.new(0))
puts "\n=== Final env: #{env.inspect} ==="

# Restore
File.delete('transform_debug.rb')
