require 'parserbase'
require 'sexp'
require 'utils'
require 'shunting'

class Parser < ParserBase
  def initialize(s)
    @s = s
    @sexp = SEXParser.new(s)
    @shunting = OpPrec::parser(s, self)
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
      @s.nolfws
      expect(Atom)
      # FIXME: Store
    end

    args = [(rest ? [name.to_sym, :rest] : name.to_sym)]
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
    # This is needed because of ugly constructs like "while cond do end"
    # where the "do .. end" block belongs to "while", not to any function
    # in the condition.
    @shunting.keywords << :do
    ret = @sexp.parse || @shunting.parse
    @shunting.keywords.delete(:do)
    ret
  end

  # if ::= "if" ws* condition defexp* "end"
  def parse_if
    expect("if") or return
    ws
    cond = parse_condition or expected("condition for 'if' block")
    @s.nolfws; expect(";")
    exps = zero_or_more(:defexp)
    expect("end") or expected("expression or 'end' for open 'if'")
    return [:if, cond, [:do]+exps]
  end

  # when ::= "when" ws* condition (nolfws* ":")? ws* defexp*
  def parse_when
    expect("when") or return
    ws
    cond = parse_condition or expect("condition for 'when'")
    @s.nolfws
    expect(":")
    ws
    exps = zero_or_more(:defexp)
    [:when, cond, exps]
  end

  # case ::= "case" ws* condition when* ("else" ws* defexp*) "end"
  def parse_case
    expect("case") or return
    ws
    cond = parse_condition or expect("condition for 'case' block")
    ws
    whens = zero_or_more(:when)
    ws
    if expect("else")
      ws
      elses = zero_or_more(:defexp)
    end
    ws
    expect("end") or expected("'end' for open 'case'")
    [:case, cond, whens, elses].compact
  end


  # while ::= "while" ws* condition "do"? defexp* "end"
  def parse_while
    expect("while") or return
    ws
    cond = parse_condition or expected("condition for 'while' block")
    @s.nolfws; expect(";") or expect("do")
    @s.nolfws;
    exps = zero_or_more(:defexp)
    expect("end") or expected("expression or 'end' for open 'while' block")
    return [:while, cond, [:do]+exps]
  end

  # rescue ::= "rescue" (nolfws* name nolfws* ("=>" ws* name)?)? ws defexp*
  def parse_rescue
    expect("rescue") or return
    @s.nolfws
    if c = parse_name
      @s.nolfws
      if expect("=>")
        ws
        name = parse_name or expected("variable to hold exception") 
      end
    end
    ws
    exps = zero_or_more(:defexp)
    return [:rescue, c, name, exps]
  end

  # begin ::= "begin" ws* defexp* rescue? "end"
  def parse_begin
    expect("begin") or return
    ws
    exps = zero_or_more(:defexp)
    rescue_ = parse_rescue
    expect("end") or expected("expression or 'end' for open 'begin' block")
    return [:block, [], exps, rescue_]
  end

  # subexp ::= exp nolfws* ("if" ws* condition)?
  def parse_subexp
    exp = @shunting.parse or return nil
    @s.nolfws
    if expect("if")
      ws
      cond = parse_condition or expected("condition for 'if' statement modifier")
      @s.nolfws; expect(";")
      exp = [:if, cond, exp]
    end
    return exp
  end

  # Later on "defexp" will allow anything other than "def"
  # and "class".
  # defexp ::= sexp | while | begin | case | if | subexp
  def parse_defexp
    ws
    ret = parse_sexp || parse_while || parse_begin || parse_case || parse_if || parse_subexp
    ws; expect(";"); ws
    ret
  end

  # block_body ::=  ws * defexp*
  def parse_block_exps
    ws
    exps = zero_or_more(:defexp)
    vars = deep_collect(exps, Array) {|node| node[0] == :assign ? node[1] : nil}
    [vars, exps]
  end

  def parse_block(start = nil)
    return nil if start == nil and !(start = expect("{")  || expect("do"))
    close = (start.to_s == "{") ? "}" : "end"
    ws
    args = []
    if expect("|")
       ws
      begin
        ws
        if name = parse_name
          args << name
          ws
        end
      end while name and expect(",")
      ws
      expect("|")
    end
    exps = parse_block_exps
    ws
    expect(close) or expected("'#{close.to_s}' for '#{start.to_s}'-block")
    return [:block] if args.size == 0 and !exps[1] || exps[1].size == 0
    [:block, args, exps[1]]
  end


  # def ::= "def" ws* name args? block_body
  def parse_def
    expect("def") or return
    ws
    name = parse_name || @shunting.parse or expected("function name")
    if (expect("."))
      name = [name]
      ret = parse_name or expected("name following '#{name}.'")
      name << ret
    end
    args = parse_args || []
    expect(";")
    vars, exps = parse_block_exps
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
    return [type.to_sym, name, exps]
  end

  # require ::= "require" ws* quoted
  def parse_require
    expect("require") or return
    ws
    q = expect(Quoted) or expected("name of source to require")
    ws
    return [:require, q]
  end

  # include ::= "include" ws* name w
  def parse_include
    expect("include") or return
    ws
    n = parse_name or expected("name of module to include")
    ws
    [:include, n]
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

