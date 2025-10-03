$: << "."
require 'driver'
require 'pp'

code = File.read('test_nested_simple.rb')
compiler = Compiler.new(['--norequire'])
require 'stringio'
exp = compiler.parse(StringIO.new(code), '<test>')
compiler.preprocess(exp)

puts "=== After preprocessing ==="
PP.pp(exp, $stdout)
