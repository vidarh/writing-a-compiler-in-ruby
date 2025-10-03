#!/usr/bin/env ruby
require './parser'
require './scanner'
require './ast'
require './transform'
require 'stringio'
require 'pp'
require 'set'

if ARGV.empty?
  puts "Usage: #{$0} <ruby_file>"
  exit 1
end

code = File.read(ARGV[0])
io = StringIO.new(code)
scanner = Scanner.new(io)
parser = Parser.new(scanner)
ast = parser.parse

# Extract just the test method for cleaner output
test_method = nil
ast.each do |node|
  if node.is_a?(Array) && node[0] == :defm && node[1] == :test
    test_method = node
    break
  end
end

if test_method
  puts "=" * 80
  puts "ORIGINAL TEST METHOD AST"
  puts "=" * 80
  pp test_method
end

# We need the full Compiler class loaded
require './compiler'

# Create a minimal compiler instance
debugger = Compiler.new

puts "\n" + "=" * 80
puts "AFTER find_vars"
puts "=" * 80

# Run find_vars on the test method
if test_method
  freq = Hash.new(0)
  # Extract the body (test_method[3])
  body = test_method[3]
  puts "Processing body..."
  vars, env = debugger.find_vars(body, [Set.new], Set.new, freq)
  puts "\nVariables collected: #{vars.inspect}"
  puts "Environment needed: #{env.inspect}"
  puts "Frequency: #{freq.select{|k,v| v > 0}.inspect}"

  puts "\n" + "=" * 80
  puts "TRANSFORMED BODY"
  puts "=" * 80
  pp test_method[3]
end

# Now look at nested procs specifically
puts "\n" + "=" * 80
puts "NESTED PROC ANALYSIS"
puts "=" * 80

def analyze_procs(node, depth = 0)
  return unless node.is_a?(Array)

  if node[0] == :proc || node[0] == :lambda
    puts "  " * depth + "#{node[0]} with params: #{node[1].inspect}"
    if node[2]
      puts "  " * depth + "  Body: #{node[2].inspect[0..100]}..."
      # Check if body is wrapped in :let
      if node[2].is_a?(Array) && node[2][0] == :let
        puts "  " * depth + "  Has :let wrapper"
        puts "  " * depth + "  Local vars: #{node[2][1].inspect}"
      end
    end
    # Recurse into body
    analyze_procs(node[2], depth + 1) if node[2]
  else
    node.each { |child| analyze_procs(child, depth) }
  end
end

if test_method
  analyze_procs(test_method)
end

puts "\n" + "=" * 80
puts "DONE"
puts "=" * 80
