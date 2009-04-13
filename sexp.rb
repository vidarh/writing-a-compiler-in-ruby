require 'parserbase'

# Simple Recursive-Descent s-expression parser
class SEXParser < ParserBase

  def initialize(s)
    @s = s # The scanner
  end

  def parse
    expect("%s") or return
    parse_sexp or expected("s-expression")
  end

  def parse_sexp
    expect("(") or return
    ws
    exprs = zero_or_more(:exp)
    expect(")") or expected("')'")
    return exprs
  end

  def parse_exp
    ws
    ret = expect(Atom, Int, Quoted) || parse_sexp
    ws
    return ret
  end
end

