require './parser'
require './ast'
require './scanner'
require 'stringio'

code = File.read(ARGV[0])
io = StringIO.new(code)
scanner = Scanner.new(io)
parser = Parser.new(scanner)
ast = parser.parse

require 'pp'
pp ast
