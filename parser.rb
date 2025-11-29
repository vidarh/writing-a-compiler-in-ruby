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
  def parse_arglist(extra_stop_tokens = [])
    # Check for argument forwarding: ... (Ruby 2.7+)
    # This must come before checking for range operators
    saved_pos = @scanner.position
    if literal(".")
      if literal(".")
        if literal(".")
          # This is ... argument forwarding
          # Return special marker for argument forwarding
          return [[:forward_args]]
        else
          # Not ..., backtrack
          @scanner.unget(".")
          @scanner.unget(".")
        end
      else
        # Not .., backtrack
        @scanner.unget(".")
      end
    end

    # Check for nested destructuring: |(a, b)|
    if literal("(")
      ws
      # Parse nested argument list
      nested_args = parse_arglist([")"])
      ws
      literal(")") or expected("')' to close destructuring")
      # Build destruct node - keep nested structure, don't flatten
      args = [[:destruct] + nested_args]
      # Check if there are more parameters after the destructuring
      nolfws
      if literal(COMMA)
        ws
        more = parse_arglist(extra_stop_tokens) or expected("argument")
        return args + more
      end
      return args
    end

    # Check for **, *, or & prefix
    prefix = nil
    if literal(ASTERISK)
      # Check if it's ** (keyword splat) or * (splat)
      if literal(ASTERISK)
        prefix = "**"
      else
        prefix = ASTERISK
      end
    elsif literal(AMP)
      prefix = AMP
    end

    ws if prefix
    ## FIXME: If "name" is not mentioned here, it is not correctly recognised
    name = nil
    if !(name = parse_name)
      # Allow bare splat (e.g., def foo(*); end) - use special name :_
      # Also allow bare keyword splat (e.g., def foo(**); end)
      # Also allow bare block (e.g., def foo(&); end) - anonymous block forwarding (Ruby 3.1+)
      if prefix == ASTERISK || prefix == "**" || prefix == AMP
        name = :_
      elsif prefix
        expected("argument name following '#{prefix}'")
      else
        return
      end
    end

    nolfws
    default = nil
    is_keyword_arg = false

    # Build stop tokens list for default value parsing
    # Include ; as stop token since it's a statement separator
    stop_tokens = [COMMA, ";"] + extra_stop_tokens

    # Check for keyword argument syntax: name: or name: value
    if literal(":")
      is_keyword_arg = true
      nolfws
      # Check if there's a default value after the colon
      # Peek to see if next token is not comma/close paren/pipe
      peek_char = @scanner.peek
      if peek_char != "," && peek_char != ")" && peek_char != "|"
        default = @shunting.parse(stop_tokens)
      end
    elsif literal("=")
      nolfws
      default = @shunting.parse(stop_tokens)
    end

    if prefix == "**"
      args = [[name.to_sym, :keyrest]]
    elsif prefix == ASTERISK
      args = [[name.to_sym, :rest]]
    elsif prefix == AMP
      args = [[name.to_sym, :block]]
    elsif is_keyword_arg
      # Keyword argument: kw: or kw: default
      if default
        args = [[name.to_sym, :key, default]]
      else
        args = [[name.to_sym, :keyreq]]
      end
    elsif default
      args = [[name.to_sym, :default, default]]
    else
      args = [name.to_sym]
    end
    nolfws
    literal(COMMA) or return args
    ws
    # Check for trailing comma: if next char is a close delimiter, allow it
    peek_char = @scanner.peek
    if peek_char == ")" || peek_char == "|"
      # Trailing comma is allowed, return current args
      return args
    end
    more = parse_arglist(extra_stop_tokens) or expected("argument")
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
    # ; is also inhibited since it's a statement separator after the condition
    pos = position
    ret = @sexp.parse || @shunting.parse([:do, ";", "\n"])
    return ret
  end

  # if_unless ::= ("if"|"unless") if_body
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
    if elseexps
      ret << E[:do].concat(elseexps)
    else
      ret << E[:do, :nil]
    end
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

  # Parse pattern contents inside Hash[...] or Array[...]
  # Handles special pattern syntax like a:, b: (keyword pattern bindings)
  def parse_pattern_list
    patterns = []

    loop do
      ws
      break if @scanner.peek == ']' || @scanner.peek == ')'

      # Parse a single pattern element
      # Try to parse keyword pattern (a:, a: value) or positional pattern
      name = parse_name
      if name
        ws
        if literal(':')
          # Keyword pattern - could be shorthand (a:) or full (a: 0)
          ws
          # Check if this is shorthand (followed by comma or close) or full form
          next_char = @scanner.peek
          if next_char == ',' || next_char == ')' || next_char == ']'
            # Shorthand: a: (binds key :a to variable a)
            patterns << E[:pattern_key, name]
          else
            # Full form: a: value
            # Use shunting with stop tokens to avoid consuming comma
            value = @shunting.parse([',', ')', ']'])
            if !value
              expected("value after ':' in pattern")
            end
            # Create a pair for hash pattern matching
            patterns << E[:pair, E[:sexp, name.inspect.to_sym], value]
          end
          ws
          if literal(',')
            ws
            next
          else
            break
          end
        else
          # Just a name, could be a constant or variable
          patterns << name
          ws
          if literal(',')
            ws
            next
          else
            break
          end
        end
      else
        # Check for hash splat: ** or **rest
        # Need to handle this specially before parse_subexp because
        # bare ** has no operand and would fail in shunting yard
        if literal('**')
          ws
          rest_var = parse_name
          if rest_var
            patterns << E[:hash_splat, rest_var]
          else
            patterns << E[:hash_splat]
          end
          ws
          if literal(',')
            ws
            next
          else
            break
          end
        end

        # Try to parse other pattern forms
        exp = parse_subexp
        break if !exp
        patterns << exp
        ws
        if literal(',')
          ws
          next
        else
          break
        end
      end
    end

    patterns
  end

  # Parse a bare hash pattern like: a: 1, b: 2
  # Called when we've already consumed the first name and seen that it's followed by :
  # first_name: the name we already consumed
  # Returns a hash node
  def parse_hash_pattern_after_name(first_name)
    pairs = []

    # Process first pair (name already consumed)
    ws
    literal(':') or expected("':' after hash pattern key")
    ws
    value = parse_subexp
    if !value
      expected("value after ':' in hash pattern")
    end
    pairs << E[:pair, E[:sexp, first_name.inspect.to_sym], value]

    # Parse remaining pairs
    loop do
      ws
      break unless literal(',')
      ws
      name = parse_name
      break if !name
      ws
      literal(':') or expected("':' after hash pattern key")
      ws
      value = parse_subexp
      if !value
        expected("value after ':' in hash pattern")
      end
      pairs << E[:pair, E[:sexp, name.inspect.to_sym], value]
    end

    return E[:hash] + pairs
  end

  # Parse a pattern for pattern matching (Ruby 3.0+)
  # Handles special syntax like Hash[a:, b:] and bare hash patterns like a: 1, b: 2
  def parse_pattern
    pos = position

    # Try to parse a constant name followed by [ or (
    name = parse_name
    if name
      ws
      # Check for ConstantName[pattern] or ConstantName(pattern) syntax
      if literal('[')
        # Parse pattern list inside brackets using special pattern syntax
        ws
        pattern_contents = parse_pattern_list
        ws
        literal(']') or expected("']' to close pattern")
        # Return as a pattern node: [:pattern, ConstantName, contents]
        return E[pos, :pattern, name] + pattern_contents
      elsif literal('(')
        # Parse pattern list inside parentheses
        ws
        pattern_contents = parse_pattern_list
        ws
        literal(')') or expected("')' to close pattern")
        return E[pos, :pattern, name] + pattern_contents
      elsif literal('=>')
        # AS pattern: ConstantName => var (e.g., Integer => n)
        # Matches the type and binds to the variable
        ws
        var = parse_name
        if !var
          expected("variable name after '=>' in AS pattern")
        end
        return E[pos, :as_pattern, name, var]
      elsif @scanner.peek == ':'
        # Bare hash pattern like a: 1, b: 2 (name already consumed)
        return parse_hash_pattern_after_name(name)
      else
        # Bare name - variable binding pattern (e.g., "in a")
        # Just return the name as-is
        return name
      end
    end

    # Check for bare hash splat pattern: in ** or in **rest
    # This pattern matches any hash
    if literal('**')
      ws
      rest_var = parse_name
      if rest_var
        return E[pos, :hash_splat, rest_var]
      else
        return E[pos, :hash_splat]
      end
    end

    # Fall back to regular condition parsing for other patterns
    parse_condition
  end

  # in ::= "in" ws* pattern (nolfws* (":" | "then" | ";"))? ws* defexp*
  # Pattern matching branch for case statements (Ruby 3.0+)
  def parse_in
    pos = position
    keyword(:in) or return
    ws
    pattern = parse_pattern or expected("pattern for 'in'")
    nolfws
    literal(COLON) || keyword(:then) || literal(SEMICOLON)
    ws
    # Use :in instead of :when to distinguish pattern matching branches
    return E[:in, pattern, parse_opt_defexp]
  end

  # case ::= "case" ws* condition? (when|in)* ("else" ws* defexp*) "end"
  # When condition is omitted, each when tests its expressions as booleans
  # Ruby 3.0+ supports 'in' branches for pattern matching
  def parse_case
    pos = position
    keyword(:case) or return
    ws
    cond = parse_condition  # Condition is optional
    nolfws; literal(";"); ws  # Consume optional ; after condition
    # Parse both 'when' and 'in' branches
    branches = kleene { parse_when || parse_in }
    ws
    elses = nil  # FIXME: Self-hosted compiler doesn't initialize local vars to nil.
                 # Without this, elses contains garbage when there's no else clause.
    if keyword(:else)
      ws
      elses = parse_opt_defexp
    end
    ws
    keyword(:end) or expected("'end' for open 'case'")
    # Don't compact - cond can be nil for case-without-condition
    # Only compact the elses if nil
    result = E[pos, :case, cond, branches]
    result << elses if elses
    return result
  end


  # while ::= "while" ws* condition "do"? defexp* "end"
  def parse_while_until_body(type)
    pos = position
    ws
    cond = parse_condition or expected("condition for '#{type.to_s}' block")
    nolfws; literal(SEMICOLON); nolfws; keyword(:do)
    nolfws;
    exps = parse_opt_defexp
    keyword(:end) or expected("expression or 'end' for open '#{type.to_s}' block")
    return E[pos, type, cond, [:do]+exps]
  end

  # for ::= "for" ws+ lvalue ws+ "in" ws+ expr ws* (SEMICOLON | ws+ "do") ws* defexp* "end"
  # Supports: for x in array, for a,b in array (destructuring), for a, in array (trailing comma)
  def parse_for
    pos = position
    keyword(:for) or return
    ws
    # Parse loop variable(s) - can be single var, method call, or destructured (a, b, c)
    # Use shunting yard parser with 'in' as inhibit to stop at 'in' keyword
    # This allows "for obj.attr in array" and "for a, b in array"
    vars = []
    # Parse first variable/lvalue - could be simple name or complex expression like obj.attr
    first_var = @shunting.parse([:in, COMMA])
    vars << (first_var or expected("variable name or expression after 'for'"))
    ws
    while literal(",")
      ws
      # Check if 'in' follows (trailing comma case: "for a, in array")
      if keyword(:in)
        # Put back 'in' and break - we'll parse it below
        @scanner.unget("in")
        break
      end
      # Check for splat (e.g., "for i, * in array" or "for i, *j in array")
      if literal(ASTERISK)
        ws
        # Check if 'in' follows immediately (bare splat: "for i, * in array")
        if keyword(:in)
          @scanner.unget("in")
          vars << :_
        else
          # Named splat: "for i, *j in array"
          name = parse_name or expected("variable name or 'in' after splat in for loop")
          vars << name
        end
      else
        # Parse next variable - could be name or complex expression
        next_var = @shunting.parse([:in, COMMA])
        vars << (next_var or expected("variable name or expression in for loop"))
      end
      ws
    end
    # Expect 'in' keyword
    keyword(:in) or expected("'in' keyword after for loop variable")
    ws
    # Parse the enumerable expression
    enumerable = parse_condition or expected("expression after 'in'")
    nolfws; literal(SEMICOLON); nolfws; keyword(:do)
    nolfws;
    # Parse body
    exps = parse_opt_defexp
    keyword(:end) or expected("expression or 'end' for open 'for' block")
    # Return [:for, vars, enumerable, body]
    # If single var, unwrap from array for simpler AST
    var = vars.length == 1 ? vars[0] : [:destruct] + vars
    return E[pos, :for, var, enumerable, [:do]+exps]
  end

  # parse_for_body - like parse_for but doesn't consume 'for' keyword
  # Used when 'for' is treated as operator in shunting yard
  def parse_for_body
    pos = position
    ws
    # Parse loop variable(s) - can be single var, method call, or destructured (a, b, c)
    vars = []
    # Parse first variable/lvalue
    first_var = @shunting.parse([:in, COMMA])
    vars << (first_var or expected("variable name or expression after 'for'"))
    ws
    while literal(",")
      ws
      if keyword(:in)
        @scanner.unget("in")
        break
      end
      if literal(ASTERISK)
        ws
        if keyword(:in)
          @scanner.unget("in")
          vars << :_
        else
          name = parse_name or expected("variable name or 'in' after splat in for loop")
          vars << name
        end
      else
        next_var = @shunting.parse([:in, COMMA])
        vars << (next_var or expected("variable name or expression in for loop"))
      end
      ws
    end
    keyword(:in) or expected("'in' keyword after for loop variable")
    ws
    enumerable = parse_condition or expected("expression after 'in'")
    nolfws; literal(SEMICOLON); nolfws; keyword(:do)
    nolfws;
    exps = parse_opt_defexp
    keyword(:end) or expected("expression or 'end' for open 'for' block")
    var = vars.length == 1 ? vars[0] : [:destruct] + vars
    return E[pos, :for, var, enumerable, [:do]+exps]
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
      # Parse assignable expression (allows self&.foo, @ivar, etc.)
      # Similar to for loop variable parsing - allows complex lvalues
      # Inhibit newline and statement keywords to stop at rescue body
      name = @shunting.parse(["\n", :end, :rescue, :else, :elsif, :ensure]) or expected("variable to hold exception")
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
    return parse_begin_body
  end

  # Shared method to parse rescue/else/ensure clauses
  # Used by both begin...end and do...end blocks
  # Returns [exps, rescue_, ensure_body]
  def parse_rescue_else_ensure(exps = [])
    pos = position
    rescue_clauses = []

    # Parse expressions until we hit rescue or a terminator
    loop do
      ws
      if keyword(:rescue)
        # Found rescue keyword - parse it properly
        nolfws
        c = parse_name  # Optional exception class
        nolfws
        name = nil
        if literal("=>")
          # Parse assignable expression (allows self&.foo, @ivar, etc.)
          # Similar to for loop variable parsing - allows complex lvalues
          # Inhibit newline and statement keywords to stop at rescue body
          name = @shunting.parse(["\n", :end, :rescue, :else, :elsif, :ensure]) or expected("variable to hold exception")
        end
        ws
        body = parse_opt_defexp
        rescue_clauses << E[pos, :rescue, c, name, body]
        # Don't break - continue to parse more rescue clauses
      else
        # Use parse_exp to handle protected, class bodies, etc.
        exp = parse_exp
        break if !exp
        exps << exp
      end
    end

    # Parse additional rescue clauses if we already have some
    while rescue_clauses.size > 0
      ws
      if keyword(:rescue)
        pos = position
        nolfws
        c = parse_name
        nolfws
        name = nil
        if literal("=>")
          name = @shunting.parse(["\n", :end, :rescue, :else, :elsif, :ensure]) or expected("variable to hold exception")
        end
        ws
        body = parse_opt_defexp
        rescue_clauses << E[pos, :rescue, c, name, body]
      else
        break
      end
    end

    # If we didn't parse any rescue in the loop, try parse_rescue
    if rescue_clauses.empty?
      single_rescue = parse_rescue
      rescue_clauses << single_rescue if single_rescue
    end

    # Combine multiple rescue clauses into one if needed
    rescue_ = rescue_clauses.empty? ? nil : (rescue_clauses.size == 1 ? rescue_clauses[0] : [:rescues] + rescue_clauses)

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

    # If we have an else clause, append it to the rescue clause
    if else_body && rescue_
      rescue_ = E[rescue_.position, :rescue, rescue_[1], rescue_[2], rescue_[3], else_body]
    end

    return [exps, rescue_, ensure_body]
  end

  def parse_begin_body
    pos = position
    ws
    exps, rescue_, ensure_body = parse_rescue_else_ensure([])
    ws
    keyword(:end) or expected("'end' for open 'begin' block")

    # Return block with ensure as 5th element
    # [:block, args, exps, rescue_clause, ensure_body]
    return E[pos, :block, [], exps, rescue_, ensure_body]
  end

  # subexp ::= exp nolfws*
  def parse_subexp
    pos = position
    # Inhibit ; and newline at statement level - they're separators, not :do operator
    # Inside parentheses, ; and newline will still work as :do operator (see shunting.rb)
    # Also inhibit case statement keywords (when, in, else, end) to prevent them from
    # being consumed as operators when they should start new branches
    ret = @shunting.parse([";", "\n", :when, :in, :else, :end, :elsif, :ensure, :rescue])
    if ret.is_a?(Array)
      ret = E[pos] + ret
    end
    nolfws
    return ret
  end

  # parse_stabby_lambda ::= "->" *ws ("(" args ")")? *ws block
  #                       | "->" *ws args *ws block
  def parse_stabby_lambda
    pos = position
    keyword(:stabby_lambda) or return
    ws

    # Parse inline parameters: ->(x, y) { } or -> x, y { }
    args = []
    if literal("(")
      # Parenthesized parameters: ->(x, y, z=1, *rest, &block) { }
      # Use parse_arglist to handle defaults, splats, blocks, etc.
      ws
      args = parse_arglist([")"])  || []
      ws
      literal(")") or expected("')'")
      ws
    else
      # Try to parse bare parameters: -> x, y { } or -> *a, b { }
      # Only parse parameters if we don't see { or do
      do_token = expect(:do)
      if do_token
        # Found 'do' - unget it for parse_block to consume
        @scanner.unget(do_token)
      elsif @scanner.peek != "{"
        # No block start yet, parse bare parameters using parse_arglist
        # This handles splat (*a), block (&b), keyword args, etc.
        # Pass { and :do as stop tokens to prevent default values from consuming the lambda body
        args = parse_arglist(["{", :do]) || []
      end
      ws
    end

    block = parse_block or expected("do .. end block")

    # If we have inline args, create a proc with those args
    # Otherwise use the block's args directly
    if args.size > 0
      block_body = block[2] || []  # block is [:proc, args, body]
      return E[pos, :lambda, args, block_body]
    end

    return E[pos, :lambda, *block[1..-1]]
  end

  # lambda ::= "lambda" *ws block (no inline parameters allowed)
  def parse_lambda
    pos = position
    keyword(:lambda) or return
    ws
    block = parse_block or expected("do .. end block")
    return E[pos, :lambda, *block[1..-1]]
  end

  def parse_next
    pos = position
    return nil if !keyword(:next)
    exps = parse_subexp
    return E[pos, :next, exps] if exps
    return E[pos, :next]
  end

  # Later on "defexp" will allow anything other than "def"
  # and "class".
  # defexp ::= sexp | while | begin | case | if | lambda | subexp
  def parse_defexp
    pos = position
    ws
    # Consume leading semicolons (empty statements)
    while literal(";"); ws; end
    ret = parse_def || parse_alias || parse_sexp ||
          parse_subexp || parse_case || parse_require_relative || parse_require
    if ret.respond_to?(:position)
      ret.position = pos
    # FIXME: @bug this below is needed for MRI, but not for the selfhosted compiler...
    # Unsure why, but they should not behave differently...
    elsif ret.is_a?(Array)
      ret = E[pos].concat(ret)
    end
    nolfws
    #if sym = expect(:if, :while, :rescue)
    #  # FIXME: This is likely the wrong way to go in some situations involving blocks
    #  # that have different semantics - parser may need a way of distinguishing them
    #  # from "normal" :if/:while
    #  ws
    #  cond = parse_condition or expected("condition for '#{sym.to_s}' statement modifier")
    #  nolfws; literal(SEMICOLON)
    #  ret = E[pos, sym.to_sym, cond, ret]
    #end
    ws; literal(";"); ws
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
      # Use parse_arglist to support default values, splats, and block parameters
      # Pass [PIPE] as extra stop token so default values stop at the closing |
      args = parse_arglist([PIPE]) || []
      ws
      literal(PIPE)
    end
    # Use shared rescue/else/ensure parsing
    exps, rescue_, ensure_body = parse_rescue_else_ensure([])

    ws
    literal(close) or expected("'#{close.to_s}' for '#{start.to_s}'-block")

    # Return proc node with rescue and ensure support
    return E[pos, :proc] if args.size == 0 && exps.size == 0 && !rescue_ && !ensure_body
    return E[pos, :proc, args, exps, rescue_, ensure_body]
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
        # Visibility modifier not followed by def, so put it back with whitespace
        # We need to include a space to separate from what follows
        @scanner.unget(" ")
        @scanner.unget(vis.to_s)
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

    # Check for endless method definition: def name(args) = expr
    # This is Ruby 3.0+ syntax for single-expression methods
    nolfws
    if literal("=")
      ws
      # Parse the expression (method body) - use parse_condition to get full expression
      # parse_condition handles operators and complex expressions properly
      expr = parse_condition or expected("expression for endless method definition")
      # Endless methods can't have rescue/ensure, so return simple defm node
      return E[pos, :defm, name, args, [expr]]
    end

    # Parse method body - parse_block_exps will naturally stop at keywords like rescue/ensure/end
    exps = parse_block_exps
    #STDERR.puts exps.inspect

    # Parse optional rescue clause (similar to parse_begin)
    rescue_ = nil
    ws
    if keyword(:rescue)
      nolfws
      c = parse_name  # Optional exception class
      nolfws
      name_var = nil
      if literal("=>")
        # Parse assignable expression (allows self&.foo, @ivar, etc.)
        # Similar to for loop variable parsing - allows complex lvalues
        # Inhibit newline and statement keywords to stop at rescue body
        name_var = @shunting.parse(["\n", :end, :rescue, :else, :elsif, :ensure]) or expected("variable to hold exception")
      end
      ws
      # parse_opt_defexp will naturally stop at ensure/end keywords
      rescue_body = parse_opt_defexp
      rescue_ = E[pos, :rescue, c, name_var, rescue_body]
    end

    # Parse optional ensure clause (similar to parse_begin)
    ensure_body = nil
    ws
    if keyword(:ensure)
      ws
      # parse_opt_defexp will naturally stop at end keyword
      ensure_body = parse_opt_defexp
    end

    ws
    #STDERR.puts @scanner.position.inspect
    keyword(:end) or expected("expression or 'end' for open def '#{name.to_s}'")

    # If we have rescue or ensure, wrap exps in a :block node
    if rescue_ || ensure_body
      body = E[pos, :block, [], exps, rescue_, ensure_body]
      return E[pos, :defm, name, args, body]
    else
      return E[pos, :defm, name, args, exps]
    end
  end

  def parse_sexp; @sexp.parse; end

  # module ::= "module" ws* name ws* exp* "end"
  def parse_module
    pos = position
    type = keyword(:module) or return
    ws
    # Check for global namespace (::ModuleName)
    global_namespace = false
    if literal('::')
      ws
      global_namespace = true
    end

    name = expect(Atom) || literal('<<') or expected("module name")
    if name
      # Check for namespaced module name (e.g., Foo::Bar::Baz)
      # Build up [:deref, :Foo, :Bar, :Baz] for module Foo::Bar::Baz
      while literal('::')
        ws
        next_part = expect(Atom) or expected("module name after ::")
        name = [:deref, name, next_part]
      end
      # Mark as global namespace if :: prefix was present
      if global_namespace
        name = [:global, name]
      end
    end
    ws
    error("A module can not have a super class") if @scanner.peek == ?<
    exps = kleene { parse_exp }
    keyword(:end) or expected("expression or \'end\'")
    return E[pos, type.to_sym, name, :Object, exps]
  end

  # Like parse_module but for when 'module' keyword has already been consumed
  def parse_module_body
    pos = position
    ws
    # Check for global namespace (::ModuleName)
    # In Ruby, ::A means "module A in the global namespace"
    # We'll represent this as [:global, :A] so the compiler knows to emit at top level
    global_namespace = false
    if literal('::')
      ws
      global_namespace = true
    end

    name = expect(Atom) || literal('<<') or expected("module name")
    if name
      # Check for namespaced module name (e.g., Foo::Bar::Baz)
      # Build up [:deref, :Foo, :Bar, :Baz] for module Foo::Bar::Baz
      while literal('::')
        ws
        next_part = expect(Atom) or expected("module name after ::")
        name = [:deref, name, next_part]
      end
      # Mark as global namespace if :: prefix was present
      if global_namespace
        name = [:global, name]
      end
    end
    ws
    error("A module can not have a super class") if @scanner.peek == ?<
    # Parse module body with optional rescue/ensure
    exps, rescue_, ensure_body = parse_rescue_else_ensure([])
    keyword(:end) or expected("expression or \'end\'")

    # If rescue or ensure present, wrap body in a block node
    # This ensures compiler sees: [:module, name, :Object, [:block, [], exps, rescue, ensure]]
    if rescue_ || ensure_body
      body = E[pos, :block, [], exps, rescue_, ensure_body]
      return E[pos, :module, name, :Object, body]
    else
      return E[pos, :module, name, :Object, exps]
    end
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
    elsif name
      # Check for namespaced class name (e.g., Foo::Bar::Baz)
      # Build up [:deref, :Foo, :Bar, :Baz] for class Foo::Bar::Baz
      while literal('::')
        ws
        next_part = expect(Atom) or expected("class name after ::")
        name = [:deref, name, next_part]
      end
    end
    ws
    # FIXME: Workaround for initialization error
    superclass = nil
    if literal("<")
      ws
      # Accept any expression as superclass (e.g., class Foo < Bar, class Foo < get_class(), etc.)
      # Invalid superclasses (like strings, integers) will raise TypeError at runtime
      superclass = parse_subexp or expected("superclass")
    end
    exps = kleene { parse_exp }
    keyword(:end) or expected("expression or 'end'")
    return E[pos, type.to_sym, name, superclass || :Object, exps]
  end

  # Like parse_class but for when 'class' keyword has already been consumed
  def parse_class_body
    pos = position
    ws
    # Check for global namespace (::ClassName)
    # In Ruby, ::A means "class A in the global namespace"
    # We'll represent this as [:global, :A] so the compiler knows to emit at top level
    global_namespace = false
    if literal('::')
      ws
      global_namespace = true
    end

    name = expect(Atom) || literal('<<') or expected("class name")
    if name == "<<"
      ob = parse_subexp
      name = [:eigen, ob]
    elsif name
      # Check for namespaced class name (e.g., Foo::Bar::Baz)
      # Build up [:deref, :Foo, :Bar, :Baz] for class Foo::Bar::Baz
      while literal('::')
        ws
        next_part = expect(Atom) or expected("class name after ::")
        name = [:deref, name, next_part]
      end
      # Mark as global namespace if :: prefix was present
      if global_namespace
        name = [:global, name]
      end
    end
    ws
    # FIXME: Workaround for initialization error
    superclass = nil
    if literal("<")
      ws
      # Accept any expression as superclass (e.g., class Foo < Bar, class Foo < get_class(), etc.)
      # Invalid superclasses (like strings, integers) will raise TypeError at runtime
      superclass = parse_subexp or expected("superclass")
    end
    # Parse class body with optional rescue/ensure
    exps, rescue_, ensure_body = parse_rescue_else_ensure([])
    keyword(:end) or expected("expression or 'end'")

    # If rescue or ensure present, wrap body in a block node
    # This ensures compiler sees: [:class, name, superclass, [:block, [], exps, rescue, ensure]]
    if rescue_ || ensure_body
      body = E[pos, :block, [], exps, rescue_, ensure_body]
      return E[pos, :class, name, superclass || :Object, body]
    else
      return E[pos, :class, name, superclass || :Object, exps]
    end
  end

  # alias ::= "alias" ws* new_name ws* old_name
  # Method names can be regular identifiers or operator method names like []=, +, etc.
  def parse_alias
    pos = position
    keyword(:alias) or return
    ws
    new_name = expect(Methodname) or expected("new method name")
    ws
    old_name = expect(Methodname) or expected("old method name")
    return E[pos, :alias, new_name, old_name]
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

    # Only attempt static require for string literals
    # Variables (Symbol), expressions (Array), or norequire mode become runtime calls
    if !q.is_a?(String) || @opts[:norequire]
      STDERR.puts "WARNING: NOT processing require for #{q.inspect} - will be runtime call"
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

    # Only attempt static require_relative for string literals
    # Variables (Symbol), expressions (Array), or norequire mode become runtime calls
    if !q.is_a?(String) || @opts[:norequire]
      STDERR.puts "WARNING: NOT processing require_relative for #{q.inspect} - will be runtime call"
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
    ret = parse_def || parse_alias || parse_defexp || literal("protected")
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
    exps = kleene { parse_exp }
    # Flatten nested :do blocks from semicolon sequences
    exps.each do |exp|
      if exp.is_a?(Array) && exp[0] == :do
        res.concat(exp[1..-1])
      else
        res << exp
      end
    end
    ws
    error("Expected EOF") if scanner.peek
    return res
  end
end
