require 'parserbase'

# Simple Recursive-Descent s-expression parser
class SEXParser < ParserBase

  def initialize(scanner)
    super(scanner)
  end

  def parse
    expect("%s") or return
    ret = parse_sexp or expected("s-expression")
    E[:sexp, ret]
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

