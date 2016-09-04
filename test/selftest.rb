
#
# This is a set of *minimal* self-hosted test cases to aid in verifying step by step that 
# core parts of the compiler itself acts the same when run under MRI as when run by itself
# It on purpose does not use any unit testing framework in order to minimize dependencies,
# given that as of writing the commpiler is by no means complete.
#
# It is also not meant to be a comprehensive set of test cases, but to test just whatever
# is needed to ensure the compiler can compile itself and a more reasonable test suite.
#
# That means avoiding all "magic".
#
# Run with:
#
#    ruby -I . test/selftest.rb
#
# Compile and run with:
#
#    ./compile test/selftest.rb -I.
#    /tmp/selftest
#

require 'scanner'
require 'parserbase'
require 'sym'
require 'atom'
require 'tokens'
require 'quoted'
require 'sexp'

require 'regalloc'
require 'function'

require 'utils'
require 'pp'
require 'treeoutput'

require 'tokenizeradapter'
require 'operators'

require 'parser'
require 'shunting'
require 'register'
require 'iooutput'
require 'arrayoutput'

require 'regalloc'
require 'emitter'

require 'scope'
require 'globalscope'
require 'classcope'
require 'funcscope'
require 'sexpscope'
require 'localvarscope'
require 'print_sexp'
require 'vtableoffsets'

require 'ast'
#require 'value'

class MockIO
  def initialize str
    @str = str
    @pos = 0
  end

  def to_str
    @str
  end

  def getc
    ch = @str[@pos]
    @pos += 1
    ch
  end
end

def expect_eq(left, right, message)
  if left == right
    puts "PASS: #{message} [expected/got #{right.inspect}]"
  else
    puts "FAIL: #{message} [expected #{right.inspect}, got #{left.inspect}]"
  end
end

def test_array
  a = []

  expect_eq(a.length, 0, "#length on empty array")

  b = [42,43,44]
  expect_eq(b.length, 3, "#length on 3-element array")

  e = b.delete_at(1)
  expect_eq(e, 43, "[42,43,44].delete_at(1) should return 43")
  expect_eq(b.inspect, "[42, 44]", "[42, 44].inspect should return [42, 44]")
  expect_eq(b.length, 2, "#length after [42,43,44].delete_at(1)")
  e = b.delete_at(0)
  expect_eq(e, 42, "[42,44].delete_at(0) should return 42")
  expect_eq(b.length, 1, "#length after [42,44].delete_at(0)")
  e = b.delete_at(0)
  expect_eq(e, 44, "[44].delete_at(0) should return 44")
  expect_eq(b.length, 0, "#length after [44].delete_at(0)")

  expect_eq([32].member?(32),true, "member? should return true if an element exists in the array")
end

# Test our own Mock first...
#
def test_mockio
  m = MockIO.new("")
  expect_eq(m.is_a?(File), false, "mockio.is_a?(File)")
  expect_eq(File.file?(m), false, "File.file?(MockIO.new")
end

def test_scannerstring
  s = Scanner::ScannerString.new("Test")

  expect_eq(s, "Test", "ScannerString and String with same contents")
end

def test_scanner_basics
  io = MockIO.new("This is a test")
  s = Scanner.new(io)

  expect_eq(s.filename,"<stream>", "Scanner#filename for non-file IO")

  expect_eq(s.peek, ?T, "scanner.peek on 'This is a test'")
  expect_eq(s.get, "T", "scanner.get on 'This is a test'")
  expect_eq(s.get, "h", "scanner.get with 'his is a test' remaining")
  s.unget("h");
  expect_eq(s.get, "h", "scanner.get with 'his is a test' remaining after unget")

  expect_eq(s.expect("is"),"is", "scanner.expect('is') with 'is a test' remaining")
end


def test_parserbase_basics
  io = MockIO.new("This is a test")
  s  = Scanner.new(io)
  pb = ParserBase.new(s)

  expect_eq(pb.expect("This"),"This", "parser.expect('This')")
  expect_eq(pb.ws,nil, "Skip whitespace")
  expect_eq(pb.expect("is"),"is", "parser.expect('is') after skipping whitespace")
end

def test_sym
  io = MockIO.new(":sym @ivar $global $var42 @with_underscore")
  s  = Scanner.new(io)

  expect_eq(Tokens::Sym.expect(s), :":sym", "Parse symbol :sym")
end

def test_atom
  io = MockIO.new(":sym @ivar $global $var42 @with_underscore")
  s  = Scanner.new(io)

  expect_eq(Tokens::Atom.expect(s), :":sym", "Parse atom :sym")
end

# The full version of respond_to? is a pre-requisite for the s-exp parsing
def test_respond_to
  expect_eq(Object.new.respond_to?(:foo), false, "Object.new.respond_to?(:foo)?")
  expect_eq(Object.new.respond_to?(:inspect), true, "Object.new.respond_to?(:inspect)?")
end

def mock_scanner(str)
  io = MockIO.new(str)
  Scanner.new(io)
end

def test_sexp_basics
  s  = mock_scanner("%s(this is a test)")
  sx = SEXParser.new(s)

  tree = sx.parse

  expect_eq(tree.inspect, "[:sexp, [:this, :is, :a, :test]]", "Parsing %s(this is a test)")
end

def test_tokenizer
  s  = mock_scanner(":sym test 123 'foo' +")
  t = Tokens::Tokenizer.new(s,nil)

  ar = []
  t.each do |token,oper|
    ar << [token,oper]
  end
#  p ar
end


def mock_shunting(str)
  s = mock_scanner(str)
  OpPrec.parser(s, nil)
end


def test_shunting
  expect_eq(mock_shunting("5 + 1").parse.inspect, "[:+, 5, 1]", "Shunting 1")
  expect_eq(mock_shunting("5 + y").parse.inspect, "[:+, 5, :y]", "Shunting 2")
  expect_eq(mock_shunting("5 + 1 * 2").parse.inspect, "[:+, 5, [:*, 1, 2]]", "Shunting 3")
end


def mock_parse(str)
  parser = Parser.new(mock_scanner(str))
  parser.parse(false).inspect
end

def test_exp(exp, result)
  m = mock_parse(exp)
  expect_eq(m, result, "Parsing '#{exp}' with the full parser")
end

def test_parser
  test_exp("%s(this is a test)", "[:do, [:sexp, [:this, :is, :a, :test]]]")
  test_exp("5 + a", "[:do, [:+, 5, :a]]")
  test_exp("puts 'Hello World'", "[:do, [:call, :puts, \"Hello World\"]]")
  test_exp("def foo; end", "[:do, [:defm, :foo, [], []]]")
  test_exp("def foo; puts 'Hello World'; end", "[:do, [:defm, :foo, [], [[:call, :puts, \"Hello World\"]]]]")
end

def test_destructuring
  test_exp("a,b = [42,123]", [:do, [:assign, [:destruct, :a, :b],[:array, 42,123]]])
end

test_array
test_mockio
test_scannerstring
test_scanner_basics
test_parserbase_basics
test_sym
test_atom
test_respond_to
test_sexp_basics
test_tokenizer
test_shunting
test_parser
test_destructuring

