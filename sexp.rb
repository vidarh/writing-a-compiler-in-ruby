require 'scanner'
require 'tokens'
require 'pp'

# Simple Recursive-Descent s-expression parser
class SEXParser
  include Tokens

  def initialize s
    @s = s # The scanner
  end

  def ws
    while (c = @s.peek) && [9,10,13,32].member?(c) do @s.get; end
  end

  def parse
    ws
    return nil if !@s.expect("%s")
    return parse_sexp || raise("Expected s-expression")
  end

  def parse_sexp
    return nil if !@s.expect("(")
    ws
    exprs = []
    while exp = parse_exp; exprs << exp; end
    raise "Expected ')'" if !@s.expect(")")
    return exprs
  end

  def parse_exp
    ws
    (ret = @s.expect(Atom) || @s.expect(Int) || @s.expect(Quoted) || parse_sexp) && ws
    return ret
  end
end

