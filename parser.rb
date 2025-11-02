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

  ASTERISK="*"
  AMP="&"
  LP="("
  RP=")"
  COMMA=","
  COLON=":"
  SEMICOLON=";"
  PIPE="|"

  # arglist ::= ("*" ws*)? name nolfws* ("," ws* arglist)?
  def parse_arglist
    prefix = literal(ASTERISK) || literal(AMP)
    ws if prefix
    ## FIXME: If "name" is not mentioned here, it is not correctly recognised
    name = nil
    if !(name = parse_name)
      # Allow bare splat (e.g., def foo(*); end) - use special name :_
      if prefix == ASTERISK
        name = :_
      elsif prefix
        expected("argument name following '#{prefix}'")
      else
        return
      end
    end

    nolfws
    default = nil
    if literal("=")
      nolfws
      default = @shunting.parse([COMMA])
    end

    if prefix then args = [[name.to_sym, prefix == ASTERISK ? :rest : :block]]
    elsif default
      args = [[name.to_sym, :default, default]]
    else
      args = [name.to_sym]
    end
    nolfws
    literal(COMMA) or return args
    ws
    more = parse_arglist or expected("argument")
    return args + more
  end

  # args ::= nolfws* ( "(" ws* arglist ws* ")" | arglist )
  def parse_args
    nolfws
    if literal(LP)
      ws; args = parse_arglist; ws
      literal(RP) or expected("')'")
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
    nolfws; literal(";")
    nolfws; keyword(:then); ws;
    exps = parse_opt_defexp
    ws

    # FIXME: Workaround for intialization error
    elseexps = nil
    if keyword(:elsif)
      # We treat "if ... elif ... else ... end" as shorthand for "if ... else if ... else ... end; end"
      elseexps = [parse_if_body(:if)]
    else
      if keyword(:else)
        ws
        elseexps = parse_opt_defexp
      end
      keyword(:end) or expected("expression or 'end' for open 'if'")
    end
    ret = E[pos,type.to_sym, cond, E[:do].concat(exps)]
    ret << E[:do].concat(elseexps) if elseexps
    return  ret
  end

  # when ::= "when" ws* condition (nolfws* (":" | "then" | ";"))? ws* defexp*
  def parse_when
    pos = position
    keyword(:when) or return
    ws
    cond = parse_condition or expected("condition for 'when'")
    nolfws
    literal(COLON) || keyword(:then) || literal(SEMICOLON)
    ws
    return E[:when, cond, parse_opt_defexp]
  end

  # case ::= "case" ws* condition when* ("else" ws* defexp*) "end"
  def parse_case
    pos = position
    keyword(:case) or return
    ws
    cond = parse_condition or expected("condition for 'case' block")
    ws
    whens = kleene { parse_when }
    ws
    elses = nil  # FIXME: Self-hosted compiler doesn't initialize local vars to nil.
                 # Without this, elses contains garbage when there's no else clause.
    if keyword(:else)
      ws
      elses = parse_opt_defexp
    end
    ws
    keyword(:end) or expected("'end' for open 'case'")
    return E[pos, :case, cond, whens, elses].compact
  end


  # while ::= "while" ws* condition "do"? defexp* "end"
  def parse_while
    pos = position
    keyword(:while) or return
    ws
    cond = parse_condition or expected("condition for 'while' block")
    nolfws; literal(SEMICOLON); nolfws; keyword(:do)
    nolfws;
    exps = parse_opt_defexp
    keyword(:end) or expected("expression or 'end' for open 'while' block")
    return E[pos, :while, cond, [:do]+exps]
  end

  # rescue ::= "rescue" (nolfws* name nolfws* ("=>" ws* name)?)? ws defexp*
  # Supports: rescue, rescue => e, rescue Error, rescue Error => e
  def parse_rescue
    pos = position
    keyword(:rescue) or return
    nolfws
    c = parse_name  # Optional exception class
    nolfws
    name = nil
    # Check for => regardless of whether exception class was provided
    if literal("=>")
      ws
      name = parse_name or expected("variable to hold exception")
    end
    ws
    body = parse_opt_defexp
    return E[pos, :rescue, c, name, body]
  end

  # begin ::= "begin" ws* defexp* rescue? "end"
  def parse_begin
    pos = position
    keyword(:begin) or return
    ws
    # Parse expressions until we hit rescue or end
    # Problem: parse_defexp may consume 'rescue' as a statement modifier
    # If so, we'll get a :rescue node with wrong structure
    exps = []
    rescue_ = nil
    loop do
      # Check for rescue keyword before parse_defexp
      # We manually parse rescue inline to handle "rescue => e" syntax correctly
      # For other keywords (else/ensure/end), we let parse_defexp naturally stop
      # when it sees them (keywords cause shunting yard to exit)
      ws
      if keyword(:rescue)
        # Found rescue keyword - parse it properly
        # Need to "put back" the rescue keyword for parse_rescue
        # We do this by manually calling parse_rescue's body
        nolfws
        c = parse_name  # Optional exception class
        nolfws
        name = nil
        if literal("=>")
          ws
          name = parse_name or expected("variable to hold exception")
        end
        ws
        body = parse_opt_defexp
        rescue_ = E[pos, :rescue, c, name, body]
        break
      end
      exp = parse_defexp
      break if !exp
      # Check if parse_defexp consumed a rescue modifier
      # Rescue modifiers have structure: [:rescue, rval, lval] (3 elements)
      # Proper rescue clauses have: [:rescue, class, name, body] (4 elements)
      if exp.is_a?(Array) && exp[0] == :rescue && exp.size == 3
        # This is a malformed rescue from modifier syntax
        # exp[1] is the first body expression, exp[2] is nil
        # Need to parse the rest of the rescue body
        rescue_body = [exp[1]]
        # Continue parsing expressions until we hit 'end'
        loop do
          ws
          break if keyword(:end)
          e = parse_defexp
          break if !e
          rescue_body << e
        end
        rescue_ = E[exp.position, :rescue, nil, nil, rescue_body]
        # Don't break - we need to continue to consume 'end'
        return E[pos, :block, [], exps, rescue_]
      elsif exp.is_a?(Array) && exp[0] == :rescue && exp.size == 4
        # Proper rescue clause
        rescue_ = exp
        break
      end
      exps << exp
    end
    # If we don't have rescue yet, try to parse it (it's optional)
    if !rescue_
      rescue_ = parse_rescue
    end

    # Parse optional else clause (only valid if rescue exists)
    else_body = nil
    ws
    if keyword(:else)
      if !rescue_
        expected("'rescue' before 'else' clause")
      end
      ws
      else_body = parse_opt_defexp
    end

    # Parse optional ensure clause (can exist with or without rescue)
    ensure_body = nil
    ws
    if keyword(:ensure)
      ws
      ensure_body = parse_opt_defexp
    end

    ws
    keyword(:end) or expected("'end' for open 'begin' block")

    # If we have an else clause, append it to the rescue clause
    # rescue_ is [:rescue, class, name, body]
    # We'll extend it to [:rescue, class, name, body, else_body]
    if else_body && rescue_
      rescue_ = E[rescue_.position, :rescue, rescue_[1], rescue_[2], rescue_[3], else_body]
    end

    # Return block with ensure as 5th element
    # [:block, args, exps, rescue_clause, ensure_body]
    return E[pos, :block, [], exps, rescue_, ensure_body]
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
    keyword(:lambda) or return
    ws
    block = parse_block or expected("do .. end block")
    return E[pos, :lambda, *block[1..-1]]
  end

  def parse_break
    pos = position
    return nil if !keyword(:break)
    exps = parse_subexp
    # FIXME: Compiler @bug workaround:
    # Current splat handling crashes if argument is not
    # an array.
    exps = Array(exps) if exps
    return E[pos, :break, *exps] if exps
    return E[pos, :break]
  end

  def parse_next
    pos = position
    return nil if !keyword(:next)
    exps = parse_subexp
    # FIXME: Compiler @bug workaround:
    # Current splat handling crashes if argument is not
    # an array.
    exps = Array(exps)
    return E[pos, :next, *exps]
  end

  # Later on "defexp" will allow anything other than "def"
  # and "class".
  # defexp ::= sexp | while | begin | case | if | lambda | subexp
  def parse_defexp
    pos = position
    ws
    ret = parse_class || parse_module || parse_sexp || parse_while || parse_begin || parse_if_unless || parse_break || parse_next || parse_lambda || parse_subexp || parse_case || parse_require_relative || parse_require
    if ret.respond_to?(:position)
      ret.position = pos
    # FIXME: @bug this below is needed for MRI, but not for the selfhosted compiler...
    # Unsure why, but they should not behave differently...
    elsif ret.is_a?(Array)
      ret = E[pos].concat(ret)
    end
    nolfws
    if sym = expect(:if, :while, :rescue)
      # FIXME: This is likely the wrong way to go in some situations involving blocks
      # that have different semantics - parser may need a way of distinguishing them
      # from "normal" :if/:while
      ws
      cond = parse_condition or expected("condition for '#{sym.to_s}' statement modifier")
      nolfws; literal(SEMICOLON)
      ret = E[pos, sym.to_sym, cond, ret]
    end
    #ws; literal(";"); ws
    return ret
  end

  def parse_opt_defexp
    kleene { parse_exp }
  end

  # block_body ::=  ws * defexp*
  def parse_block_exps
    ws
    kleene { parse_exp }
  end

  def parse_block(start = nil)
    pos = position
    return nil if start == nil and !(start = expect("{",:do))
    close = (start.to_s == "{") ? "}" : :end
    ws
    args = []
    if literal(PIPE)
      ws
      # FIXME:
      # This is a workaround, as
      # "begin ... end while ...." does not
      # yet work correctly.
      while name = parse_name
        args << name
        ws
        break if !literal(COMMA)
        ws
      end
      ws
      literal(PIPE)
    end
    exps = parse_block_exps
    ws
    literal(close) or expected("'#{close.to_s}' for '#{start.to_s}'-block")
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

  # def ::= ("private"|"protected"|"public")? ws* "def" ws* name args? block_body
  def parse_def
    pos = position
    saved_pos = @scanner.position

    # Try to parse optional visibility modifier followed by def
    # If we see a visibility keyword not followed by def, backtrack
    vis = keyword(:private) || keyword(:protected) || keyword(:public)
    if vis
      saved_after_vis = @scanner.position
      ws
      if !keyword(:def)
        # Visibility modifier not followed by def, so backtrack completely
        @scanner.position = saved_pos
        return nil
      end
    else
      # No visibility modifier, just try to parse def
      keyword(:def) or return nil
    end

    ws
    name = parse_defname
    args = parse_args || []
    literal(";")
    exps = parse_block_exps
    keyword(:end) or expected("expression or 'end' for open def '#{name.to_s}'")
    return E[pos, :defm, name, args, exps]
  end

  def parse_sexp; @sexp.parse; end

  # module ::= "module" ws* name ws* exp* "end"
  def parse_module
    pos = position
    type = keyword(:module) or return
    ws
    name = expect(Atom) || literal('<<') or expected("class name")
    ws
    error("A module can not have a super class") if @scanner.peek == ?<
    exps = kleene { parse_exp }
    keyword(:end) or expected("expression or \'end\'")
    return E[pos, type.to_sym, name, :Object, exps]
  end

  # class ::= ("class" ws* (name|'<<') ws* (< ws* superclass)? ws* name ws* exp* "end"
  def parse_class
    pos = position
    type = keyword(:class) or return
    ws
    name = expect(Atom) || literal('<<') or expected("class name")
    if name == "<<"
      ob = parse_subexp
      name = [:eigen, ob]
    end
    ws
    # FIXME: Workaround for initialization error
    superclass = nil
    if literal("<")
      ws
      superclass = expect(Atom) or expected("superclass")
    end
    exps = kleene { parse_exp }
    keyword(:end) or expected("expression or 'end'")
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
      f = File.exist?(path) ? File.open(path) : nil
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
    keyword(:require) or return
    ws
    q = parse_subexp or expected("name of source to require")
    ws

    if q.is_a?(Array) || @opts[:norequire]
      STDERR.puts "WARNING: NOT processing require for #{q.inspect}"
      return E[pos, :require, q]
    end

    self.require(q)
  end

  def parse_require_relative
    pos = position
    keyword(:require_relative) or return
    ws
    q = parse_subexp or expected("name of source to require_relative")
    ws

    # require_relative needs to resolve the path relative to the current file
    # For now, treat it like require (the compile-time handling will need to be updated)
    if q.is_a?(Array) || @opts[:norequire]
      STDERR.puts "WARNING: NOT processing require_relative for #{q.inspect}"
      return E[pos, :require, q]
    end

    # Resolve relative to current file
    if @scanner.filename
      dir = File.dirname(@scanner.filename)
      if !q.start_with?('/')
        # Use expand_path to normalize ".." and make absolute
        q = File.expand_path(File.join(dir, q))
      end
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
    ret = parse_class || parse_module || parse_def || parse_defexp || literal("protected")
    if ret.is_a?(Array)
      ret = E[pos].concat(ret)
    elsif ret.respond_to?(:position) && !ret.position
      ret.position = pos
    end
    ws; expect(SEMICOLON); ws
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
    res.concat(kleene { parse_exp })
    ws
    error("Expected EOF") if scanner.peek
    return res
  end
end
