require 'parserbase'
require 'sexp'

class Parser < ParserBase
  def initialize s
    @s = s
    @sexp = SEXParser.new(s)
  end

  # name ::= atom
  def parse_name
    @s.expect(Atom)
  end

  # args ::= ws* sexp
  def parse_args
    @s.ws # We should probably require no linefeed here.
    @sexp.parse
  end

  # Later on "defexp" will allow anything other than "def"
  # and "class". For now, that's only sexp's.
  # defexp ::= sexp
  def parse_defexp
    @s.ws
    @sexp.parse
  end

  # def ::= "def" ws* name args? ws* defexp* "end"
  def parse_def
    return nil if !@s.expect("def")
    @s.ws
    raise "Expected function name" if !(name = parse_name)
    args = parse_args
    @s.ws
    exps = [:do] + zero_or_more(:defexp)
    raise "Expected expression of 'end'" if !@s.expect("end")
    return [:defun, name, args, exps]
  end

  def parse_sexp; @sexp.parse; end

  # exp ::= ws* (def | sexp)
  def parse_exp
    @s.ws
    parse_def || parse_sexp
  end

  # program ::= exp* ws*
  def parse
    res = [:do] + zero_or_more(:exp)
    @s.ws
    raise "Expected EOF" if @s.peek
    return res
  end
end
