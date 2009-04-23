require 'parserbase'
require 'sexp'
require 'utils'
require 'shunting'

class Parser < ParserBase
  @@requires = {}

  def initialize(scanner, opts = {})
    super(scanner)
    @opts = opts
    @sexp = SEXParser.new(scanner)
    @shunting = OpPrec::parser(scanner, self)
  end

  # name ::= atom
  def parse_name
    expect(Atom)
  end

  # arglist ::= ("*" ws*)? name nolfws* ("," ws* arglist)?
  def parse_arglist
    prefix = expect("*") || expect("&")
    ws if prefix
    if !(name = parse_name)
      expected("argument name following '#{prefix}'") if prefix
      return
    end

    nolfws
    if expect("=")
      nolfws
      @shunting.parse([","])
      # FIXME: Store
    end

    if prefix then args = [[name.to_sym, prefix == "*" ? :rest : :block]]
    else args = [name.to_sym]
    end
    nolfws
    expect(",") or return args
    ws
    more = parse_arglist or expected("argument")
    return args + more
  end

  # args ::= nolfws* ( "(" ws* arglist ws* ")" | arglist )
  def parse_args
    nolfws
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

  # if ::= "if" ws* condition "then"? defexp* "end"
  def parse_if
    expect("if") or return
    ws
    cond = parse_condition or expected("condition for 'if' block")
    nolfws; expect(";")
    nolfws; expect("then"); ws;
    exps = zero_or_more(:defexp)
    ws
    if expect("else")
      ws
      elseexps = zero_or_more(:defexp)
    end
    expect("end") or expected("expression or 'end' for open 'if'")
    ret = [:if, cond, [:do]+exps]
    ret << [:do]+elseexps if elseexps
    return  ret
  end

  # when ::= "when" ws* condition (nolfws* ":")? ws* defexp*
  def parse_when
    expect("when") or return
    ws
    cond = parse_condition or expect("condition for 'when'")
    nolfws
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
    nolfws; expect(";") or expect("do")
    nolfws;
    exps = zero_or_more(:defexp)
    expect("end") or expected("expression or 'end' for open 'while' block")
    return [:while, cond, [:do]+exps]
  end

  # rescue ::= "rescue" (nolfws* name nolfws* ("=>" ws* name)?)? ws defexp*
  def parse_rescue
    expect("rescue") or return
    nolfws
    if c = parse_name
      nolfws
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

  # subexp ::= exp nolfws*
  def parse_subexp
    ret = @shunting.parse
    nolfws
    ret
  end

  # Later on "defexp" will allow anything other than "def"
  # and "class".
  # defexp ::= sexp | while | begin | case | if | subexp
  def parse_defexp
    ws
    ret = parse_sexp || parse_while || parse_begin || parse_case || parse_if || parse_subexp
    nolfws
    if sym = expect("if") || expect("while") || expect("rescue")
      # FIXME: This is likely the wrong way to go in some situations involving blocks
      # that have different semantics - parser may need a way of distinguishing them
      # from "normal" :if/:while
      ws
      cond = parse_condition or expected("condition for '#{sym.to_s}' statement modifier")
      nolfws; expect(";")
      ret = [sym.to_sym, cond, ret]
    end
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
    ret = parse_block_exps
    exps = [:let,ret[0]] + ret[1]
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


  # Returns the include paths relative to a given filename.
  def rel_include_paths(filename)
    [filename,"#{filename}.rb","lib/#{filename}","lib/#{filename}.rb"]
  end


  # Statically including a require'd file
  #
  # Not sure if I think this really belong in the parser,
  # as opposed to being handled as post-processing later -
  # may refactor this as a separate tree-rewriting step later.
  def require q
    return @@requires[q] if @@requires[q]
    STDERR.puts "NOTICE: Statically requiring '#{q}'"
    # FIXME: Handle include path
    paths = rel_include_paths(q)
    f = nil
    paths.detect { |path| f = File.open(path) rescue nil }
    error("Unable to load '#{q}'") if !f
    s = Scanner.new(f)
    @@requires[q] = Parser.new(s,@opts).parse(false)
  end

  # require ::= "require" ws* subexp
  def parse_require
    expect("require") or return
    ws
    q = parse_subexp or expected("name of source to require")
    ws

    if q.is_a?(Array) || @opts[:norequire]
      STDERR.puts "WARNING: NOT processing require for #{q.inspect}"
      return [:require, q]
    end

    self.require(q)
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
    ret = parse_class || parse_def || parse_require || parse_include || parse_defexp
    ws; expect(";"); ws
    ret
  end

  # program ::= exp* ws*
  def parse(require_core = true)
    res = [:do]
    res << self.require("lib/core/core.rb") if require_core and !@opts[:norequire]
    res += zero_or_more(:exp)
    ws
    error("Expected EOF") if scanner.peek
    return res
  end
end

