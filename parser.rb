require 'parserbase'
require 'sexp'
require 'utils'
require 'shunting'
require 'operators'

class Parser < ParserBase
  @@requires = {}

  attr_accessor :include_paths

  def initialize(scanner, opts = {})
    super(scanner)
    @opts = opts
    @sexp = SEXParser.new(scanner)
    # FIXME:
    # OpPrec::parser fails, though it works with MRI
    @shunting = OpPrec.parser(scanner, self)

    # FIXME: If member variable is not explicitly assigned, it
    # will be 0 rather than nil. Need to ensure instance vars
    # are cleared.
    @include_paths = nil
    @include_paths = opts[:include_paths].dup if opts[:include_paths]
    @include_paths ||= []

    path = File.expand_path(File.dirname(__FILE__)+"/lib")
    @include_paths << path

    # FIXME: This is a hack.
    @include_paths << "./lib"
  end

  # name ::= atom
  def parse_name
    expect(Atom)
  end

  # arglist ::= ("*" ws*)? name nolfws* ("," ws* arglist)?
  def parse_arglist
    prefix = expect("*") || expect("&")
    ws if prefix
    ## FIXME: If "name" is not mentioned here, it is not correctly recognised
    name = nil
    if !(name = parse_name)
      expected("argument name following '#{prefix}'") if prefix
      return
    end

    nolfws
    default = nil
    if expect("=")
      nolfws
      default = @shunting.parse([","])
    end

    if prefix then args = [[name.to_sym, prefix == "*" ? :rest : :block]]
    elsif default
      args = [[name.to_sym, :default, default]]
    else 
      args = [name.to_sym]
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
    # :do is needed in the inhibited set because of ugly constructs like
    # "while cond do end" where the "do .. end" block belongs to "while",
    # not to any function in the condition.
    pos = position
    ret = @sexp.parse || @shunting.parse([:do])
    return ret
  end

  # if_unless ::= ("if"|"unless") if_body
  def parse_if_unless
    pos = position
    type = keyword(:if) || keyword(:unless) or return
    parse_if_body(type.to_sym)
  end
  
  # FIXME: Weird parser bug: If '"then' appears together in the comment
  # line before, it causes a parse failure
  # if_body ::= ws* condition nolfws* ";"? nolfws* "then"? ws* 
  #             defexp* ws* ("elsif" if_body | ("else" defexp*)? "end") .
  def parse_if_body(type)
    pos = position
    ws
    cond = parse_condition or expected("condition for '#{type.to_s}' block")
    nolfws; expect(";")
    nolfws; expect(:then); ws;
    exps = zero_or_more(:defexp)
    ws

    # FIXME: Workaround for intialization error
    elseexps = nil
    if expect(:elsif)
      # We treat "if ... elif ... else ... end" as shorthand for "if ... else if ... else ... end; end"
      elseexps = [parse_if_body(:if)]
    else
      if expect(:else)
        ws
        elseexps = zero_or_more(:defexp)
      end
      expect(:end) or expected("expression or 'end' for open 'if'")
    end
    ret = E[pos,type.to_sym, cond, E[:do].concat(exps)]
    ret << E[:do].concat(elseexps) if elseexps
    return  ret
  end

  # when ::= "when" ws* condition (nolfws* ":")? ws* defexp*
  def parse_when
    pos = position
    expect(:when) or return
    ws
    cond = parse_condition or expected("condition for 'when'")
    nolfws
    expect(":")
    ws
    exps = zero_or_more(:defexp)
    return E[:when, cond, exps]
  end

  # case ::= "case" ws* condition when* ("else" ws* defexp*) "end"
  def parse_case
    pos = position
    expect(:case) or return
    ws
    cond = parse_condition or expected("condition for 'case' block")
    ws
    whens = zero_or_more(:when)
    ws
    if expect(:else)
      ws
      elses = zero_or_more(:defexp)
    end
    ws
    expect(:end) or expected("'end' for open 'case'")
    return E[pos, :case, cond, whens, elses].compact
  end


  # while ::= "while" ws* condition "do"? defexp* "end"
  def parse_while
    pos = position
    expect(:while) or return
    ws
    cond = parse_condition or expected("condition for 'while' block")
    nolfws; expect(";"); nolfws; expect(:do)
    nolfws;
    exps = zero_or_more(:defexp)
    expect(:end) or expected("expression or 'end' for open 'while' block")
    return E[pos, :while, cond, [:do]+exps]
  end

  # rescue ::= "rescue" (nolfws* name nolfws* ("=>" ws* name)?)? ws defexp*
  def parse_rescue
    pos = position
    expect(:rescue) or return
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
    return E[pos, :rescue, c, name, exps]
  end

  # begin ::= "begin" ws* defexp* rescue? "end"
  def parse_begin
    pos = position
    expect(:begin) or return
    ws
    exps = zero_or_more(:defexp)
    rescue_ = parse_rescue
    expect(:end) or expected("expression or 'end' for open 'begin' block")
    return E[pos, :block, [], exps, rescue_]
  end

  # subexp ::= exp nolfws*
  def parse_subexp
    pos = position
    ret = @shunting.parse
    if ret.is_a?(Array)
      ret = E[pos] + ret
    end
    nolfws
    return ret
  end

  # lambda ::= "lambda" *ws block
  def parse_lambda
    pos = position
    expect(:lambda) or return
    ws
    block = parse_block or expected("do .. end block")
    return E[pos, :lambda, *block[1..-1]]
  end

  def parse_break
    pos = position
    return nil if !expect(:break)
    return E[pos, :break]
  end

  def parse_next
    pos = position
    return nil if !expect(:next)
    exps = parse_subexp
    return E[pos, :next, *exps]
  end

  # Later on "defexp" will allow anything other than "def"
  # and "class".
  # defexp ::= sexp | while | begin | case | if | lambda | subexp
  def parse_defexp
    pos = position
    ws
    ret = parse_sexp || parse_while || parse_begin || parse_case || parse_if_unless || parse_lambda || parse_break || parse_next || parse_subexp || parse_require
    ret.position = pos if ret.respond_to?(:position)
    nolfws
    if sym = expect(:if, :while, :rescue)
      # FIXME: This is likely the wrong way to go in some situations involving blocks
      # that have different semantics - parser may need a way of distinguishing them
      # from "normal" :if/:while
      ws
      cond = parse_condition or expected("condition for '#{sym.to_s}' statement modifier")
      nolfws; expect(";")
      ret = E[pos, sym.to_sym, cond, ret]
    end
    #ws; expect(";"); ws
    return ret
  end

  # block_body ::=  ws * defexp*
  def parse_block_exps
    pos = position
    ws
    exps = zero_or_more(:defexp)
    return E[pos,*exps]
  end

  def parse_block(start = nil)
    pos = position
    return nil if start == nil and !(start = expect("{",:do))
    close = (start.to_s == "{") ? "}" : :end
    ws
    args = []
    if expect("|")
      ws
      # FIXME:
      # This is a workaround, as
      # "begin ... end while ...." does not
      # yet work correctly.
      while name = parse_name
        args << name
        ws
        break if !expect(",")
        ws
      end
      ws
      expect("|")
    end
    exps = parse_block_exps
    ws
    expect(close) or expected("'#{close.to_s}' for '#{start.to_s}'-block")
    return E[pos, :proc ] if args.size == 0 and exps.size == 0
    return E[pos, :proc, args, exps]
  end




  def parse_defname
    name = expect(Methodname) || @shunting.parse or expected("function name")
    if (expect("."))
      name = [name]
      ret = expect(Methodname) or expected("name following '#{name}.'")
      name << ret
    end
    return name
  end

  # def ::= "def" ws* name args? block_body
  def parse_def
    pos = position
    expect(:def) or return nil
    ws
    name = parse_defname
    args = parse_args || []
    expect(";")
    exps = parse_block_exps
    expect(:end) or expected("expression or 'end' for open def '#{name.to_s}'")
    return E[pos, :defm, name, args, exps]
  end

  def parse_sexp; @sexp.parse; end

  # module ::= "module" ws* name ws* exp* "end"
  def parse_module
    pos = position
    type = expect(:module) or return
    ws
    name = expect(Atom) || expect('<<') or expected("class name")
    ws
    error("A module can not have a super class") if @scanner.peek == ?<
    exps = zero_or_more(:exp)
    expect(:end) or expected("expression or \'end\'")
    return E[pos, type.to_sym, name, :Object, exps]
  end

  # class ::= ("class" ws* (name|'<<') ws* (< ws* superclass)? ws* name ws* exp* "end"
  def parse_class
    pos = position
    type = expect(:class) or return
    ws
    name = expect(Atom) || expect("\<\<") or expected("class name")
    ws
    # FIXME: Workaround for initialization error
    superclass = nil
    if expect("<")
      ws
      superclass = expect(Atom) or expected("superclass")
    end
    exps = zero_or_more(:exp)
    expect(:end) or expected("expression or 'end'")
    return E[pos, type.to_sym, name, superclass || :Object, exps]
  end


  # Returns the include paths relative to a given filename.
  def rel_include_paths(filename)
    if filename[0].chr == "/"
      if filename[-3..-1] != ".rb"
        return [filename +".rb"]
      end
      return [filename]
    end

    # FIXME: Hack due to codegen error
    # regarding using argument inside block
    fname = filename
    @include_paths.collect do |path|
      # FIXME: Hack due to codegen error
      # regarding argument inside the block
      fname
      full = File.expand_path("#{path}/#{fname}")
      full << ".rb" if full[-3..-1] != ".rb"
      full
    end
  end


  # Statically including a require'd file
  #
  # Not sure if I think this really belong in the parser,
  # as opposed to being handled as post-processing later -
  # may refactor this as a separate tree-rewriting step later.
  def require q
    return true if @@requires[q]
    # FIXME: Handle include path
    paths = rel_include_paths(q)
    f = nil

    fname = nil
    paths.detect do |path|
      fname = path
      f = File.exists?(path) ? File.open(path) : nil
    end
    error("Unable to open '#{q}'")  if !f

    # STDERR.puts "NOTICE: Statically requiring '#{q}' from #{fname}"

    # FIXME: This fails with
    #  @@requires[q] = []
    # as well as with:
    #  @@requires[q] = Array.new
    # (for apparently different reasons)
    a = Array.new
    @@requires[q] = a # Prevent include/require loops

    s = Scanner.new(f)
    pos = position
    # FIXME: Is this change also down to parser bug?
    parser =  Parser.new(s, @opts)
    expr = parser.parse(false)
    e = E[pos,:required, expr]
    @@requires[q] = e

    e
  end

  # require ::= "require" ws* subexp
  def parse_require
    pos = position
    expect(:require) or return
    ws
    q = parse_subexp or expected("name of source to require")
    ws

    if q.is_a?(Array) || @opts[:norequire]
      STDERR.puts "WARNING: NOT processing require for #{q.inspect}"
      return E[pos, :require, q]
    end

    self.require(q)
  end

  # include ::= "include" ws* name w
  def parse_include
    pos = position
    keyword(:include) or return
    ws
    n = parse_name or expected("name of module to include")
    ws
    return E[pos, :include, n]
  end

  # exp ::= ws* (class | def | sexp)
  def parse_exp
    ws
    pos = position
    ret = parse_class || parse_module || parse_def || parse_include || parse_defexp || expect("protected")
    ret = E[pos].concat(ret) if ret.is_a?(Array)
    ret.position = pos if ret.respond_to?(:position) && !ret.position
    ws; expect(";"); ws
    return ret
  end

  # program ::= exp* ws*
  def parse(require_core = true)
    res = E[position, :do]
    # FIXME: This does not work in the face of compiling the compiler somewhere where
    # the paths are different than where it will run. A lesson in the compile-time vs.
    # runtime issue.
    # res << self.require(File.expand_path(File.dirname(__FILE__)+"/lib/core/core.rb")) if require_core and !@opts[:norequire]
    res << self.require("core/core.rb") if require_core and !@opts[:norequire]
    res.concat(zero_or_more(:exp))
    ws
    error("Expected EOF") if scanner.peek
    return res
  end
end

