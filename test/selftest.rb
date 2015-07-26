
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
require 'atom'
require 'tokens'
require 'quoted'
require 'sexp'

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
  expect_eq(s.expect("is"),"is", "scanner.expect('is') with 'is is a test' remaining")
end


def test_parserbase_basics
  io = MockIO.new("This is a test")
  s  = Scanner.new(io)
  pb = ParserBase.new(s)

  expect_eq(pb.expect("This"),"This", "parser.expect('This')")
  expect_eq(pb.ws,nil, "Skip whitespace")
  expect_eq(pb.expect("is"),"is", "parser.expect('is') after skipping whitespace")
end


def test_sexp_basics
end


test_mockio
test_scannerstring
test_scanner_basics
#test_parserbase_basics



