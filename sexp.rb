require 'parserbase'

# Simple Recursive-Descent s-expression parser
class SEXParser < ParserBase

  def initialize(scanner)
    super(scanner)
  end

  def parse
    literal("%s") or return nil
    ret = parse_sexp or expected("s-expression")
    E[:sexp, ret]
  end

  def parse_sexp
    literal("(") or return
    ws
    exprs = kleene { parse_exp }
    literal(")") or expected("')'")
    return exprs
  end

  def parse_exp
    ws
    ret = expect(Atom, Int, Quoted, Methodname) || parse_sexp
    ws
    return ret
  end
end
