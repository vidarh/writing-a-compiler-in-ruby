require 'parserbase'
require 'sexp'
require 'utils'
require 'shunting'

class Parser < ParserBase
  def initialize s
    @s = s
    @sexp = SEXParser.new(s)
    @shunting = OpPrec::parser(s)
  end
  
  # name ::= atom
  def parse_name
    expect(Atom)
  end
  
  # arglist ::= ("*" ws*)? name nolfws* ("," ws* arglist)?
  def parse_arglist
    rest = expect("*")
    ws if rest
    if !(name = parse_name)
      expected("argument name following '*'") if rest
      return
    end

    @s.nolfws
    if expect("=")
      expect(Atom)
      # FIXME: Store
    end

    args = [(rest ? [name.to_sym,:rest] : name.to_sym)]
    @s.nolfws
    expect(",") or return args
    ws
    more = parse_arglist or expected("argument")
    return args + more
  end
  
  # args ::= nolfws* ( "(" ws* arglist ws* ")" | arglist )
  def parse_args
    @s.nolfws
    if expect("(")
      ws; args = parse_arglist; ws
      expect(")") or expected("')'")
      return args
    end
    return parse_arglist
  end

  # condition ::= sexp | opprecexpr
  def parse_condition
    ret = @sexp.parse || @shunting.parse
  end

  # if ::= "if" ws* condition defexp* "end"
  def parse_if
    expect("if") or return
    ws
    cond = parse_condition or expected("condition for 'if' block")
    @s.nolfws; expect(";")
    exps = zero_or_more(:defexp)
    raise "Expected expression or 'end' for open if" if !@s.expect("end")
    return [:if,cond,[:do]+exps]
  end

  # while ::= "while" ws* condition defexp* "end"
  def parse_while
    expect("while") or return
    ws
    cond = parse_condition or expected("condition for 'while' block")
    @s.nolfws; expect(";")
    exps = zero_or_more(:defexp)
    expect("end") or expected("expression or 'end' for open 'while' block")
    return [:while,cond,[:do]+exps]
  end

  # subexp ::= exp nolfws* ("if" ws* condition)?
  def parse_subexp
    exp = @shunting.parse or return nil
    @s.nolfws
    if expect("if")
      ws
      cond = parse_condition or expected("condition for 'if' statement modifier")
      @s.nolfws; expect(";")
      exp = [:if,cond,exp]
    end
    return exp
  end

  # Later on "defexp" will allow anything other than "def"
  # and "class".
  # defexp ::= sexp | while | if | subexp
  def parse_defexp
    ws
    ret = parse_sexp || parse_while || parse_if || parse_subexp
    ws; expect(";"); ws
    ret
  end

  # def ::= "def" ws* name args? ws* defexp* "end"
  def parse_def
    expect("def") or return
    ws
    name = parse_name || @shunting.parse or expected("function name")
    args = parse_args || []
    ws
    exps = zero_or_more(:defexp)
    vars = deep_collect(exps,Array) {|node| node[0] == :assign ? node[1] : nil}
    exps = [:let,vars] + exps 
    expect("end") or expected("expression or 'end' for open def")
    return [:defun, name, args, exps]
  end

  def parse_sexp; @sexp.parse; end

  # class ::= ("class"|"module") ws* name ws* exp* "end"
  def parse_class
    type = expect("class","module") or return
    ws
    name = expect(Atom) or expected("class name")
    ws
    if expect("<")
      ws
      superclass = expect(Atom) or expected("superclass")
      # FIXME: Include superclass in tree
    end
    exps = zero_or_more(:exp)
    expect("end") or expected("expression or 'end'")
    return [type.to_sym,name,exps]
  end

  # require ::= "require" ws* quoted
  def parse_require
    expect("require") or return
    ws
    q = expect(Quoted) or expected("name of source to require")
    ws
    return [:require,q]
  end

  # include ::= "include" ws* name w
  def parse_include
    expect("include") or return
    ws
    n = parse_name or expected("name of module to include")
    ws
    [:include,n]
  end

  # exp ::= ws* (class | def | sexp)
  def parse_exp
    ws
    ret = parse_class || parse_def || parse_defexp || parse_require || parse_include
    ws; expect(";"); ws
    ret
  end

  # program ::= exp* ws*
  def parse
    res = [:do] + zero_or_more(:exp)
    ws
    raise "Expected EOF" if @s.peek
    return res
  end
end

