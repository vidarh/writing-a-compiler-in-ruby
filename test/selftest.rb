
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

# FIXME: At some point globals seems to have broken.
# Don't output PASS's
# $quiet = true

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
require 'compiler'

class MockParser
  def parse_block
    [:proc]
  end
end

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

# FIXME: The 27.chr is a workaround for parser bug
# with \e
def col(num)
  "#{27.chr}[3#{num.to_s}m"
end

def msg_pass(message, right)
#  if !$quiet
#    puts "#{col(2)}PASS#{col(7)}: #{message} [expected/got #{right.inspect}]"
#  end
end

def msg_fail(message, left,right)
  if !left.is_a?(String)
    li = left.inspect
    ri = right.inspect
  else
    li = left
    ri = right
  end
  if li.length < 50 && ri.length < 50
    puts "#{col(1)}FAIL#{col(7)}: #{message} [expected #{right.inspect}, got #{left.inspect}]"
  else
    puts "#{col(1)}FAIL#{col(7)}: #{message} [cont]"
    puts "==EXPECTED:"
    puts ri
    puts "==GOT:"
    puts li
  end
end

def expect_eq(left, right, message)
  if left == right
    msg_pass(message, right)
  else
    msg_fail(message, left, right)
  end
end

def test_fixnum
  expect_eq((40 % 10).inspect, "0", "40 % 10 == 0")
  expect_eq(42 / 7, 6, "42 / 7 == 6")
  expect_eq(4096.to_s(10), "4096", "4096.to_s(10) => '4096'")
  expect_eq(4096.inspect, "4096", "4096.inspect => '4096'")
  expect_eq(-4.to_s, "-4", "Converting -4 to a string")
  expect_eq(0 - 4, -4, "0 - 4")
  expect_eq("-4".to_i.to_s,"-4", "Converting -4 from a string to Fixnum and back")
  expect_eq((-4).to_s,"-4", "Converting -4 to a string")

  expect_eq(4 <=> 3, 1, "4 <=> 3 should return 1")
end

def test_symbol
  expect_eq(:foo == :foo, true, "Same symbol should match with #==")
  expect_eq(:foo === :foo, true, "Same symbol should match with #===")
  expect_eq(:foo.eql?(:foo), true, "Same symbol should match with #eql?")
  expect_eq(:foo != :foo, false, ":foo != :foo => false")
  expect_eq(:foo != :bar, true, ":foo != :bar => true")
  expect_eq(:foo.respond_to?(:to_sym), true, "A Symbol should respond to #to_sym")
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

  b = [42,43]
  expect_eq(b[0], 42, "b=[42,43]; b[0] should return 42")
  expect_eq(b[-1], 43, "b=[42,43]; b[-1] should return 43")
  expect_eq(b[1..-1].inspect, [43].inspect, "b=[42,43]; b[1..-1] should return [43]")

  b = [1,2,3,4]
  expect_eq(b.reverse.inspect, [4,3,2,1].inspect, "Array#reverse should reverse an array")

  # FIXME: Inlining this into the expect_eq() call causes seg-fault.
  part = [42,2,5,1].partition {|v| v > 4}
  expect_eq(part.inspect, [[42,5], [2,1]].inspect, "Array#partition should split an array in two based on provided block")

  #expect_eq([42,2,3,1].sort,     [1,2,3,42], "Array#sort")
  res = [42,2,3,1].sort_by {|v| v }
  expect_eq(res.inspect, [1,2,3,42].inspect , "Array#sort_by (ascending)")
  # FIXME: The below fails due to "-"
#  res = [42,2,3,1].sort_by {|v| -v }
#  expect_eq(res, [42,3,2,1] , "Array#sort_by (descending)")

  expect_eq(42 <=> 2, 1, "Fixnum#<=>(42,2)")
  expect_eq(42 <=> 3, 1, "Fixnum#<=>(42,3)")
  expect_eq(42 <=> 1, 1, "Fixnum#<=>(42,1)")
  expect_eq(2 <=> 3, -1, "Fixnum#<=>(2,3)")
  expect_eq(2 <=> 2, 0, "Fixnum#<=>(2,2)")
  expect_eq(3 <=> 1, 1, "Fixnum#<=>(3,1)")

  #  ary = [42,2,3,1]
  # FIXME: This causes a parse/compilation error:
  #  res = ary.partition {|e| (e <=> 2) > 0 }
  #  expect_eq(res.inspect, "[[42, 3], [2, 1]]", "partition")

  expect_eq([:a] == [:a], true, "Array#==: Two Array's where each element compares the same should return true")
  expect_eq([:foo, :a, :b, :d, :e, :f].sort, [:a, :b, :d, :e, :f, :foo], "Array#sort")

  res = [42,2,3,1].sort
  expect_eq(res.inspect, [1,2,3,42].inspect , "Array#sort (ascending)")

  res = ["true","nil", "sp"].sort
  expect_eq(res.inspect, '["nil", "sp", "true"]', "Array#sort (strings)")

  res = [:true, :nil, :sp].sort
  expect_eq(res.inspect, '[:nil, :sp, :true]', "Array#sort (symbols)")

  res = Array(42)
  expect_eq(res.inspect,"[42]", "Array(42) should return [42]")

  expect_eq([0,1,2,3,4].insert(2,42).inspect, "[0, 1, 42, 2, 3, 4]", "Array#insert with a positive offset should insert its argument *before* the value at the offset")
  expect_eq([0,1,2].insert(4,42).inspect, "[0, 1, 2, nil, 42]", "Array#insert with an offset larger than the array should cause 'nil's to be inserted to expand the array accordingly")
  expect_eq([0,1,2].insert(-1,42).inspect, "[0, 1, 2, 42]", "Array#insert with -1 as offset is the same as appending an entry at the end")
  expect_eq([0,1,2].insert(-2,42).inspect, "[0, 1, 42, 2]", "Array#insert with a negative offset is the same as counting that many places from the right, and then inserting the entry *after* that position")

  # Test the extensions to Array used by the compiler:
  a = [:stackframe]
  expect_eq(a.inspect, "[:stackframe]", "Array with a single symbol")
  expect_eq(a[1].inspect, "nil", "[:stackframe][1] should return nil")
  expect_eq(a[-1].inspect, ":stackframe", "[:stackframe][-1] should return :stackframe")
  expect_eq(a[1..-1].inspect, "[]", "[:stackframe][1..-1] should return []")

  expect_eq(([:a] - [:a]).inspect, "[]", "Subtracting identical arrays should return []")
  expect_eq(([:a, :b, :c] - [:b]).inspect, "[:a, :c]", "Subtracting part of an array should return the rest")

  expect_eq([:a, :b, :c].zip(1..3).inspect, "[[:a, 1], [:b, 2], [:c, 3]]", "Array#zip should merge the array with an enumerable")

  expect_eq([:a].flatten, [:a], "Flatten on a flat Array is a noop")
  expect_eq([:a,[:b,:c]].flatten, [:a, :b, :c], "Array#flatten on a nested array")
  expect_eq([:a,[:b,[:c]]].flatten, [:a, :b, :c], "Array#flatten on a more deeply nested array")
  expect_eq([:a,[:b,[:c]]].flatten(1), [:a, :b, [:c]], "Array#flatten(1)q on a more deeply nested array")

  # Range indexes
  a = [:a, :b]
  expect_eq(a[1..1], [:b], "Array#[]: Single element range")
  expect_eq(a[1..2], [:b], "Array#[]: Range extending past the end")
  b = [:a, :b, :c, :d, :e]
  expect_eq(b[1..2], [:b, :c], "Array#[]: Two element range")
  expect_eq(b[1..3], [:b, :c, :d], "Array#[]: Three element range")
  expect_eq(b[2..4], [:c, :d, :e], "Array#[]: Range hitting end")
end

def test_set
  s = Set.new
  s << :a
  s << :b
  s << :c
  a = [:foo, :a]

  expect_eq((s - a).inspect, "#<Set: {:b, :c}>", "Subtracting an array from a Set")
  c = [:c]
  expect_eq((s - a - c).inspect, "#<Set: {:b}>", "Chained subtration of arrays from a Set")

  s << :b
  expect_eq(s.inspect, "#<Set: {:a, :b, :c}>", "Second addition of pre-existing value to Set")
end

def test_hash

  d = Hash.new(42)
  expect_eq(d[1],42, "Verifying that Hash returns default specified default value for unknown key")

  h = {}
  h[:foo] = :bar
  expect_eq(h.inspect, "{:foo=>:bar}", "Insert single key into Hash")
  h[:a] = :b
  expect_eq(h.inspect, "{:foo=>:bar, :a=>:b}", "Inserting second key maintains insertion order")
  h[:foo] = :baz
  expect_eq(h.inspect, "{:foo=>:baz, :a=>:b}", "Replacing first inserted key maintains original insertion order")

  h[:b] = :c
  expect_eq(h.inspect, "{:foo=>:baz, :a=>:b, :b=>:c}", "Additional insertion after overwrite")

  expect_eq(h.collect.to_a.inspect, "[[:foo, :baz], [:a, :b], [:b, :c]]", "Collect should return Hash values in insertion order")

  h[:d] = :e
  h[:e] = :f
  h[:f] = :g
  expect_eq(h.inspect, "{:foo=>:baz, :a=>:b, :b=>:c, :d=>:e, :e=>:f, :f=>:g}", "Additional additions")
  expect_eq(h.keys.inspect, [:foo, :a, :b, :d, :e, :f].inspect, "#keys")

  h.delete(:d)
  expect_eq(h.keys.inspect, [:foo, :a, :b, :e, :f].inspect, "#keys post-delete")
  h[:d] = :h
  expect_eq(h.keys.inspect, [:foo, :a, :b, :e, :f, :d].inspect, "#keys post-delete and re-insert")
  h.delete(:foo)
  expect_eq(h.keys.inspect, [:a, :b, :e, :f, :d].inspect, "and another delete")
  expect_eq(h.delete(:d), :h, "Return value of delete")
  expect_eq(h.keys.inspect, [:a, :b, :e, :f].inspect, "and another delete")
  expect_eq(h.delete(nil), nil, "delete nil")
  expect_eq(h.delete(:b), :c, "Return value of delete")
  expect_eq(h.keys.inspect, [:a, :e, :f].inspect, "and another delete")
  expect_eq(h.to_a.inspect, [[:a, :b], [:e, :f], [:f, :g]].inspect, "#to_a after deletes")
  h.delete(:a)
  h.delete(:e)
  expect_eq(h.to_a.inspect, [[:f, :g]].inspect, "Last element")
end

def while_loop
  while false
  end
end

def test_while
  expect_eq(while_loop, nil, "A while loop without an explicit return should evaluation to nil")
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

  expect_eq(s.position.lineno, 1, "Scanner#position#lineno starts at 1")
  expect_eq(s.position.col, 1, "Scanner#position#col starts at 1")
  expect_eq(s.filename,"<stream>", "Scanner#filename for non-file IO")

  expect_eq(s.peek, ?T, "scanner.peek on 'This is a test'")
  expect_eq(s.position.col, 1, "Scanner#peek does not move the column")
  expect_eq(s.get, "T", "scanner.get on 'This is a test'")
  expect_eq(s.position.col, 2, "Scanner#get does move the column")
  expect_eq(s.get, "h", "scanner.get with 'his is a test' remaining")
  expect_eq(s.position.col, 3, "Scanner#get does move the column (2)")
  s.unget("h");
  expect_eq(s.position.col, 2, "Scanner#unget does move the column back")
  expect_eq(s.get, "h", "scanner.get with 'his is a test' remaining after unget")

  expect_eq(s.expect("is"),"is", "scanner.expect('is') with 'is a test' remaining")

  s.expect("a test")
  expect_eq(s.expect("x"), false, "scanner.expect('x') after having consumed the whole string should return nil")

  io = MockIO.new("foo\nbar\n")
  s = Scanner.new(io)
  s.expect("foo\n")
  expect_eq(s.position.col, 1, "Scanner position after LF should be 1")
  expect_eq(s.position.lineno, 2, "Scanner lineno should increase")
  s.unget("foo\n")
  expect_eq(s.position.lineno, 1, "Unget of a line with LF should reduce lineno")

  s = mock_scanner("%")
  s.expect("%s")
  expect_eq(s.position.lineno, 1, "A failed Scanner#expect should not change the line number")
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

  tree = SEXParser.new(mock_scanner("%s(index self -4)")).parse
  expect_eq(tree.inspect, "[:sexp, [:index, :self, -4]]", "Parsing %s(index self -4)")

end

def test_escapes
  esc = 27.chr # Doing this as comparing again "\\" if the parsing of "\\" is broken won't work very well.

  escstr = ""
  escstr << 92.chr  # \
  escstr << "e"

  expect_eq(esc.ord, 27, "esc")
  expect_eq("\ee - esc 2".ord, 27, "esc 2")
  expect_eq("\e - esc 3".length, 9, "esc 3")
  expect_eq('\e - esc 4'.ord, 92, "esc 4")
  expect_eq('\e - esc 5'.length, 10, "esc 5")
  expect_eq('\e - esc 6'[1].chr, 'e', "esc 6")

  escistr = ""
  escistr << 34.chr # "
  escistr << 92.chr # \
  escistr << 92.chr # \
  escistr << "e"
  escistr << 34.chr # "
  expect_eq(escstr.inspect, escistr, "Inspect")

  s = mock_scanner("\\e")
  expect_eq(s.expect("\\"), "\\", "Expect Scanner#expect to return quoted backslash")
  str = "\e"
  expect_eq(str.ord, 27, "Expect double-quoted string with backslash-e to translate to esc")
  s = mock_scanner(str)
  expect_eq(s.expect(esc), esc, "Expect Scanner.expect(esc) to return esc when string is esc")
  s = mock_scanner('\e')
  expect_eq(s.expect("\\"), "\\", "Expect Scanner#expect to find backslash in single-quoted '\\e'")

  str = 34.chr
  str << 92.chr
  str << 'e and more'
  str << 34.chr # "\e"
  s = mock_scanner(str)
  t = Tokens::Quoted.expect(s)
  expect_eq(t, 27.chr + " and more", "Tokens::Quotes need to be able to handle escapes")
end

def test_tokenizer
  s  = mock_scanner(":sym test 123 'foo' +")
  t = Tokens::Tokenizer.new(s,nil)

  ar = []
  t.each do |token,oper|
    ar << [token,oper]
  end

  s = mock_scanner("def foo; end")
  t = Tokens::Tokenizer.new(s,nil)
  while tok = t.get and tok[0]
    ar << tok
  end
end

def test_methodname_tokenizer
  s = mock_scanner("__flag=x")
  expect_eq(Tokens::Methodname.expect(s).inspect, ":__flag=", "__flag= is a legal method name")
end

def mock_shunting(str)
  s = mock_scanner(str)
  OpPrec.parser(s, Parser.new(s))
end


def test_shunting
  expect_eq(mock_shunting("5 + 1").parse.inspect, "[:+, 5, 1]", "Shunting 1")
  expect_eq(mock_shunting("5 + y").parse.inspect, "[:+, 5, :y]", "Shunting 2")
  expect_eq(mock_shunting("5 + 1 * 2").parse.inspect, "[:+, 5, [:*, 1, 2]]", "Shunting 3")

  # Handling of single argument with lambda wrongly used to return a non-array argument list
  expect_eq(mock_shunting("foo.bar(x) {}\n").parse.inspect, "[:callm, :foo, :bar, [:x], [:proc]]", "Shunting foo.bar(x) {}")

  expect_eq(mock_shunting('x.y 42').parse.inspect, "[:callm, :x, :y, 42]", "")
end


def mock_parse(str, require_core = false)
  parser = Parser.new(mock_scanner(str))
  parser.parse(require_core)
end

def test_exp(exp, result)
  m = mock_parse(exp).inspect
  expect_eq(m, result, "Parsing '#{exp}' with the full parser")
end

def test_parser
  test_exp("%s(this is a test)", "[:do, [:sexp, [:this, :is, :a, :test]]]")
  test_exp("5 + a", "[:do, [:+, 5, :a]]")
  test_exp("puts 'Hello World'", "[:do, [:call, :puts, [\"Hello World\"]]]")
  test_exp("def foo; end", "[:do, [:defm, :foo, [], []]]")
  test_exp("def foo; puts 'Hello World'; end", "[:do, [:defm, :foo, [], [[:call, :puts, [\"Hello World\"]]]]]")
  test_exp("e[i]", "[:do, [:callm, :e, :[], [:i]]]")
  test_exp("e[i] = E[:foo]", "[:do, [:callm, :e, :[]=, [:i, [:callm, :E, :[], [:\":foo\"]]]]]")
  test_exp('"\e"',"[:do, \"\\e\"]")
  test_exp("Set[* e[2].to_a]","[:do, [:callm, :Set, :[], [[:splat, [:callm, [:callm, :e, :[], [2]], :to_a]]]]]")
  test_exp("def foo; name.gsub(foo.bar) { }; end ","[:do, [:defm, :foo, [], [[:callm, :name, :gsub, [[:callm, :foo, :bar]], [:proc]]]]]")
  test_exp('STDERR.puts "defm: #{args.inspect}"', "[:do, [:callm, :STDERR, :puts, [[:concat, \"defm: \", [:callm, :args, :inspect]]]]]")
  test_exp('STDERR.puts "test"', "[:do, [:callm, :STDERR, :puts, \"test\"]]")
  test_exp('STDERR.puts("test")', "[:do, [:callm, :STDERR, :puts, [\"test\"]]]")
  test_exp("self.== other","[:do, [:callm, :self, :==, :other]]")

  # Testing basic operator associativity.
  test_exp("a - b - c","[:do, [:-, [:-, :a, :b], :c]]")
  test_exp("a + b + c","[:do, [:+, [:+, :a, :b], :c]]")
  test_exp("a * b * c","[:do, [:*, [:*, :a, :b], :c]]")
  test_exp("a / b / c","[:do, [:/, [:/, :a, :b], :c]]")

  test_exp("1..x.size","[:do, [:range, 1, [:callm, :x, :size]]]")

  # Handling of single argument with/without lambda
  test_exp("foo.bar(x)", "[:do, [:callm, :foo, :bar, [:x]]]")
  test_exp("foo.bar(x) {}", "[:do, [:callm, :foo, :bar, [:x], [:proc]]]")

  test_exp("def flatten level=0; end", "[:do, [:defm, :flatten, [[:level, :default, 0]], []]]")

  # Trailing ','
  test_exp("{ :foo => 42, } ","[:do, [:hash, [:pair, :\":foo\", 42]]]")
end
  prog = mock_parse("require 'core/base'\n{}\n")
  expect_eq(prog[2].position.lineno, 2, "Parser position")

  prog = mock_parse('
  class Foo
    def __x
      bar = baz
    end
  end
')
  expect_eq(prog[1][3][0][3][0].position.lineno, 4, "Parser line number should match")
def test_destructuring
  test_exp("a,b = [42,123]", "[:do, [:assign, [:destruct, :a, :b], [:array, 42, 123]]]")
end

def test_depth_first
  prog = mock_parse("a = 42")
  prog.depth_first(:defm) do |n|
    msg_fail("Testing depth_first","not to get here", "here")
  end
  msg_pass("depth_first","to get here")

  prog = [:if, [:a, :b], [:do, :c]]
  out = []
  prog.depth_first do |e|
    out << e
  end
  expect_eq(out.inspect, [[:if, [:a, :b], [:do, :c]], [:a, :b], [:do, :c]].inspect, "#depth_first should descent into each array")
end

def mock_preprocess(exp)
  prog = mock_parse(exp, false)
  #e = Emitter.new
  #c = Compiler.new(e)
  #c.preprocess(prog)
  #c.compile(prog)
end

include AST

def test_compiler
  e = Emitter.new
  c = Compiler.new(e)
  exp = [E[:assign, :foo, [:array, [:sexp, [:call, :__int, 1]]]], 
        [:callm, :foo, :each, [], E[:proc, [:e], [:arg, [:call, :puts, [:arg]]]]]]
  args = Set.new
  args << :arg
  scopes = [args]

  r = c.find_vars(exp,scopes,Set.new, Hash.new(0))
  expect_eq("[[:foo], #<Set: {:arg}>]", r.inspect, "Compiler#find_vars")

  prog = mock_parse("def __flag=x\n    42\n  end\n")
  expect_eq(prog.inspect, "[:do, [:defm, :__flag=, [:x], [42]]]", "Parse 'def __flag=(x)' without leaving out the =")
  # FIXME: The way this gets rewritten is awful, but this test does cover the current correct behaviour
  prog = mock_parse("\"\#{'foo'}\#{'bar'}\"")
  c = Compiler.new(e)
  c.rewrite_concat(prog)
  expect_eq(prog.inspect, [:do, [:callm, [:callm, [:callm, [:callm, "", :to_s], :concat, [[:callm, "foo", :to_s]]], :concat, [[:callm, "", :to_s]]], :concat, [[:callm, "bar", :to_s]]]].inspect, "concat => callm")
  prog = mock_parse('
  if a < 2
    STDERR.puts("a #{b} c")
  end
')

  c = Compiler.new(e)
  c.rewrite_concat(prog)
  expect_eq(prog.inspect, [:do, [:if, [:<, :a, 2], [:do, [:callm, :STDERR, :puts, [[:callm, [:callm, [:callm, "a ", :to_s], :concat, [[:callm, :b, :to_s]]], :concat, [[:callm, " c", :to_s]]]]]]]].inspect, "concat => callm (2)")

  dummypos = Scanner::Position.new("test", 1,1)

  c = Compiler.new
  prog = mock_parse('
    each_byte do |c|
      h = h * 33 + c
    end
  ')

  res = c.find_vars(prog, [[:h]], Set.new, Hash.new(0))
  expect_eq(res.inspect, "[[], #<Set: {:h}>]", "find_vars should identify all variables in a proc")

  c = Compiler.new
  prog = mock_parse('
    with_register_for do
      @e.save_result(scope,right)
    end
  ')

  res = c.find_vars(prog, [[:scope, :left, :right]], Set.new, Hash.new(0))
  expect_eq(res.inspect, "[[:left], #<Set: {:scope, :right}>]", "find_vars_should identify all variables in a proc")

  c = Compiler.new
  prog = mock_parse('
    with_register_for do
      @e.save_result(foo(scope,right))
    end
  ')

  res = c.find_vars(prog[1][3][2][0][3], [[:scope, :left, :right]], Set.new, Hash.new(0), true)
  expect_eq(res.inspect, "[[:left], #<Set: {:scope, :right}>]", "find_vars_should identify all variables in a proc")

  res = c.find_vars(prog[1][3][2], [[:scope, :left, :right]], Set.new, Hash.new(0), true)
  expect_eq(res.inspect, "[[:left], #<Set: {:scope, :right}>]", "find_vars_should identify all variables in a proc [x]")

  c = Compiler.new(e)
  prog = [[:call, :p, [:arg, :arg2]]]
  res = c.find_vars(prog, [[:arg,:arg2], Set.new], Set.new, Hash.new(0), true)
  expect_eq(res.inspect, "[[], #<Set: {:arg, :arg2}>]", "find_vars should identify all variables in a proc")

  prog = E[E[dummypos,:proc, [], [[:call, :p, [:arg, :arg2]]]]]
  res = c.find_vars(prog, [[:arg,:arg2]], Set.new, Hash.new(0))
  expect_eq(res.inspect, "[[], #<Set: {:arg, :arg2}>]", "find_vars should identify all variables references in method body")

  c = Compiler.new(e)
  prog = mock_parse('
  def foo
    yield
  end
')
  c.preprocess(prog)
  expect_eq(prog[1][3].inspect, "[:let, [:__env__, :__tmp_proc], [:sexp, [:assign, :__env__, [:call, :__alloc_mem, [8]]]], [:assign, [:index, :__env__, 1], :__closure__], [:callm, [:index, :__env__, 1], :call, nil]]",
    "yield triggers a rewrite even with no arguments")

end


def test_string
  expect_eq("foo".gsub("o","x"), "fxx", "String#gsub - Simple character substitution")
  expect_eq("foo".gsub("o","xy"), "fxyxy", "String#gsub - Replace character with string")
  expect_eq("foo\nbar".gsub("\n","\\n"), "foo\\nbar", "String#gsub - Replace character with string with escape characters")

  expect_eq("e" <=> "d", 1, "String#<=> should return 1 if left string sorts after right string")
  expect_eq("foo" <=> "f", 1, "String#<=> should return 1 for 'foo' <=> 'f'")

  expect_eq("foo bar baz".split(" "), ["foo", "bar", "baz"], "String#split(' ') should return an array of the split string")
end

def test_file
  expect_eq(File.expand_path('lib/core/string.rb','/app'), '/app/lib/core/string.rb', "Expanding path wo/trailing / on base")
  expect_eq(File.expand_path('lib/core/string.rb','/app/'), '/app/lib/core/string.rb', "Expanding path w/trailing / on base")
  expect_eq(File.expand_path('lib//core', '/app'), '/app/lib/core', "Expanding path w/repeated slash")
  expect_eq(File.dirname("/app/examples/case.rb"), "/app/examples", "Basic dirname")
  expect_eq(File.basename("/app/examples/case.rb"), "case.rb", "Basic basename")
end

test_fixnum
test_symbol
test_array
test_set
test_hash
test_while
test_mockio
test_scannerstring
test_scanner_basics
test_parserbase_basics
test_sym
test_atom
test_respond_to
test_sexp_basics
test_escapes
test_tokenizer
test_methodname_tokenizer
test_shunting
test_parser
test_destructuring
test_depth_first
test_string
test_file
test_compiler
