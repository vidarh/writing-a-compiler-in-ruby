#!/usr/bin/env ruby
require './parser'
require './scanner'
require './ast'
require './compiler'
require 'stringio'
require 'pp'
require 'set'

code = File.read('test_broken_shadow.rb')
io = StringIO.new(code)
scanner = Scanner.new(io)
parser = Parser.new(scanner)
ast = parser.parse

# Patch Compiler to add logging
class Compiler
  alias_method :orig_rewrite_env_vars, :rewrite_env_vars

  def rewrite_env_vars(exp, env)
    puts "rewrite_env_vars called with env: #{env.inspect}"
    result = orig_rewrite_env_vars(exp, env)
    puts "  returned: #{result}"
    result
  end
end

require './transform'
compiler = Compiler.new

# Get test method
test_method = nil
ast.each do |node|
  if node.is_a?(Array) && node[0] == :defm && node[1] == :test
    test_method = node
    break
  end
end

puts "Processing transforms..."
compiler.preprocess(ast)

puts "\n=== Test method after preprocessing ==="
pp test_method
