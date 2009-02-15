require 'scanner'
require 'tokens'
require 'pp'

# Simple Recursive-Descent s-expression parser
class SEXParser
  include Tokens

  def initialize s
    @s = s # The scanner
  end

  def parse
    return nil if !@s.expect("%s")
    return parse_sexp || raise("Expected s-expression")
  end

  def parse_sexp
    return nil if !@s.expect("(")
    @s.ws
    exprs = []
    while exp = parse_exp; exprs << exp; end
    raise "Expected ')'" if !@s.expect(")")
    return exprs
  end

  def parse_exp
    @s.ws
    (ret = @s.expect(Atom) || @s.expect(Int) || @s.expect(Quoted) || parse_sexp) && @s.ws
    return ret
  end
end

