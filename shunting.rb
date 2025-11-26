
require 'compilererror'
require 'pp'
require 'treeoutput'
require 'ast'

require 'tokenizeradapter'

module OpPrec
  class ShuntingYard
    FLATTEN= Operators["#flatten#"]
    HASH   = Operators["#hash#"]
    COMMA  = Operators[","]

    def initialize(output, tokenizer, parser, inhibit = [])
      @out = output

      # FIXME: Pass this in instead of storing it.
      @tokenizer = TokenizerAdapter.new(tokenizer,parser)
      @parser = parser

      # Pass scanner reference to output for error messages with source context
      scanner = @tokenizer.scanner
      @out.set_scanner(scanner) if scanner

      @is_call_context = false

      # Tricky hack:
      #
      # We need a call operator with high priority, but *if* parentheses are not used around
      # the arguments, we need to push an operator with *low* priority onto the operator stack to prevent
      # binding the call too tightly to the first value encountered. opcall2 below is that second, low priority
      # call operator

      @opcall  = Operators["#call#"]
      @opcall2 = Operators["#call2#"]

      @opcallm = Operators["."]

      @inhibit = inhibit
      @ostack  = []
    end

    def keywords
      @tokenizer.keywords
    end

    def reduce(ostack, op = nil)
      pri = op ? op.pri : 0
      # We check for :postfix to handle cases where a postfix operator has been given a lower precedence than an
      # infix operator, yet it needs to bind tighter to tokens preceeding it than a following infix operator regardless,
      # because the alternative gives a malfored expression.
      #
      # As a special rule only :rp's are allowed to reduce past an :lp. This is a bit of a hack - since we recurse for :lp's
      # then don't strictly need to go on the stack at all - they could be pushed on after the shunt returns. May
      # do that later.
      #
      # For PREFIX operators: Don't reduce them when a higher-precedence (lower pri) prefix operator comes next.
      # Example: "break *[1, 2]" - break (pri 22) should NOT be reduced when * (pri 8) arrives.
      # The higher-precedence operator should be processed first, then the lower-precedence one consumes it.

      while  !ostack.empty? &&
             (ostack.last.right_pri > pri ||
               (ostack.last.right_pri == pri && op.assoc == :left) ||
               ostack.last.type == :postfix) &&
             ((op && op.type == :rp) || ostack.last.type != :lp) &&
             # Don't reduce prefix operators when an equal-or-higher-precedence prefix operator follows
             # This allows "not not false" to parse as "not (not false)" instead of "(not) not false"
             !(ostack.last.type == :prefix && op && op.type == :prefix && pri <= ostack.last.pri)
        o = ostack.pop
        @out.oper(o) if o.sym
      end
    end

    def parse_block(start)
      @parser.parse_block(start)
    end

    def parse_quoted_exp
      @tokenizer.get_quoted_exp
    end

    def shunt_subexpr(ostack, src, is_call = false)
      old = @ostack
      old_is_call = @is_call_context
      @ostack = ostack
      @is_call_context = is_call
      shunt(src)
      @ostack = old
      @is_call_context = old_is_call
      :infix_or_postfix
    end

    def oper(src,token,ostack, opstate, op, lp_on_entry, possible_func, lastlp)
      #STDERR.puts "oper: #{token.inspect} / ostack=#{ostack.inspect} / opstate=#{opstate.inspect} / op=#{op.inspect}" if ENV['DEBUG_PARSER']
      #STDERR.puts "   vstack=#{@out.vstack.inspect}" if ENV['DEBUG_PARSER']

      # Handle argument forwarding: ... when used standalone in function calls
      # If we see ... with only opening paren on ostack inside foo(...), it's argument forwarding, not endless range
      # Check: @is_call_context means we're inside foo()
      #        ostack.size == 1 && ostack.first.type == :lp && ostack.first.sym == nil means we're inside (...), not [...]
      if op && op.sym == :exclusive_range &&
         ostack.size == 1 && ostack.first && ostack.first.type == :lp && ostack.first.sym == nil &&
         @is_call_context
        # This is argument forwarding in a method call: foo(...)
        # Push :forward_args value and return
        @out.value(:forward_args)
        return :infix_or_postfix
      end

      # Handle keyword argument shorthand: {a:, b:} where : is followed by ,
      # When we see comma in a hash and last operator is :ternalt, check if last token was :
      # If last token was :, then :ternalt has no right value and needs nil
      # This handles {a:, b:, c:} correctly regardless of how many keys precede
      if op && op.sym == :comma &&
         !ostack.empty? && ostack.first && ostack.first.sym == :hash &&
         ostack.last && ostack.last.sym == :ternalt &&
         src.lasttoken && src.lasttoken[0] == ":"
        @out.value(nil)
      end

      # Handle keyword argument shorthand in function calls: foo(a:, b:) where : is followed by ,
      # Similar to above but for parenthesis context (ostack.first.sym == nil)
      if op && op.sym == :comma &&
         !ostack.empty? && ostack.first && ostack.first.sym == nil &&
         ostack.last && ostack.last.sym == :ternalt &&
         src.lasttoken && src.lasttoken[0] == ":"
        @out.value(nil)
      end

      # Handle bare splat in patterns: [*, x] where * has no name
      # When we see comma/close-bracket/semicolon after * and last token was literally *, push :_ placeholder
      # This handles pattern matching syntax like "in [*, 9, *post]", "{a: [*, 9]}", and "in *;"
      # We check if lasttoken was * to ensure no variable was consumed between * and the operator
      if op && (op.sym == :comma || op.sym == :do || (op.is_a?(Hash) && op[:infix_or_postfix] && op[:infix_or_postfix].type == :rp)) &&
         !ostack.empty? && ostack.last && ostack.last.sym == :splat &&
         src.lasttoken && src.lasttoken[0] == "*"
        @out.value(:_)
      end

      # begin is always a complete expression that produces a value
      # It should be parsed regardless of whether a prefix operator is waiting
      if opstate == :prefix && op.sym == :begin_stmt
        #STDERR.puts "   begin statement"
        @out.value(@parser.parse_begin_body)
        return :infix_or_postfix  # Allow postfix while/until after begin...end
      end

      # When if/unless/while/until/rescue appear in prefix position, parse as statement UNLESS
      # they're appearing after a prefix operator (which would make them modifiers)
      if opstate == :prefix && (ostack.empty? || ostack.last.type != :prefix)
        if op.sym == :if_mod
          #STDERR.puts "   if expression"
          @out.value(@parser.parse_if_body(:if))
          return :prefix
        elsif op.sym == :unless_mod
          #STDERR.puts "   unless expression"
          @out.value(@parser.parse_if_body(:unless))
          return :prefix
        elsif op.sym == :while_mod
          #STDERR.puts "   while expression"
          @out.value(@parser.parse_while_until_body(:while))
          return :prefix
        elsif op.sym == :until_mod
          #STDERR.puts "   until expression"
          @out.value(@parser.parse_while_until_body(:until))
          return :prefix
        elsif op.sym == :for_stmt
          #STDERR.puts "   for expression"
          @out.value(@parser.parse_for_body())
          return :prefix
        elsif op.sym == :rescue_mod && ostack.length == 0
          #STDERR.puts "   rescue clause (not modifier)"
          # Unlike if/while, rescue in prefix position signals end of begin block body
          # Only break if ostack is empty (we're at statement level)
          # Otherwise, parse as expression
          src.unget(token)
          reduce(ostack)
          return :break
        elsif op.sym == :lambda_stmt
          #STDERR.puts "   lambda statement"
          # Lambda keyword already consumed, try to parse the block
          @parser.ws
          block = @parser.parse_block
          if block
            # Found a block - this is lambda do...end or lambda { }
            # Build lambda node: [:lambda, args, body, rescue, ensure]
            result = Parser::E[@parser.position, :lambda, *block[1..-1]]
            @out.value(result)
            return :prefix
          else
            # No block found - treat 'lambda' as a method name/call
            # Push :lambda as a value and mark as possible function
            @out.value(:lambda)
            possible_func = true
            return :infix_or_postfix
          end
        elsif op.sym == :class_stmt
          #STDERR.puts "   class statement"
          @out.value(@parser.parse_class_body)
          return :prefix
        elsif op.sym == :module_stmt
          #STDERR.puts "   module statement"
          @out.value(@parser.parse_module_body)
          return :prefix
        end
      end

      if op && (op.sym == :hash_or_block || op.sym == :block)
        # Don't treat { as block argument if there was a newline before current token
        # This fixes: -> { x }.a \n lambda { y } where lambda should NOT be block arg to .a
        # Also don't treat { as block argument if it's in the inhibit list (e.g., stabby lambda params)
        if (possible_func || (@ostack.last && @ostack.last.sym == :call) || @ostack.last == @opcallm) && !@tokenizer.newline_before_current && !@inhibit.include?(token)
          ocall = @ostack.last ? @ostack.last.sym == :call : false
          @out.value([]) if !ocall
          @out.value(parse_block(token))
          @out.oper(FLATTEN)
          ostack << @opcall if !ocall
        elsif op.sym == :hash_or_block
          opstate = shunt_subexpr([HASH],src)
        else
          scanner = @tokenizer.scanner
          msg = "Block not allowed here"
          raise ShuntingYardError.new(msg,
                                      scanner ? scanner.filename : nil,
                                      scanner ? scanner.lineno : nil,
                                      scanner ? scanner.col : nil)
        end
      elsif op && op.sym == :quoted_exp
        @out.value(parse_quoted_exp)
      elsif op && op.type == :rp
        # Handle empty parentheses/arrays/hashes
        if lastlp
          # Check if it's () vs [] vs {}
          # ostack.first.sym: nil for (), :array for [], :hash_or_block for {}
          first_sym = ostack.first ? ostack.first.sym : :unknown

          # For empty (), distinguish between expression context and call context
          # @is_call_context is set when entering subexpr for foo()
          if first_sym == nil && !@is_call_context
            @out.value(:nil)  # Empty () in expression: should be nil value
          else
            @out.value(nil)   # Empty [] and {} and foo() get placeholder nil
          end
        end
        @out.value(nil) if src.lasttoken and src.lasttoken[1] == COMMA
        # Before closing paren, check if there's a prefix operator with minarity=0 that needs a nil value
        # Only for parentheses (), not for blocks {} or arrays []
        if !ostack.empty? && ostack.first && ostack.first.sym == nil &&
           ostack.last.type == :prefix && ostack.last.minarity == 0
          @out.value(nil)
        end
        # Handle trailing ; before ) - infix :do operator needs its right operand
        # e.g., (1;2;) - push nil for the missing right value
        if !ostack.empty? && ostack.first && ostack.first.sym == nil &&
           ostack.last.type == :infix && ostack.last.minarity == 0 &&
           src.lasttoken && src.lasttoken[0] == ";"
          @out.value(nil)
        end
        # Handle endless ranges: if the last token was .. or ... (range operator) followed immediately by ),
        # push nil as the missing right-hand value
        if !ostack.empty? && ostack.first && ostack.first.sym == nil &&
           src.lasttoken && (src.lasttoken[0] == ".." || src.lasttoken[0] == "...") &&
           (ostack.last.sym == :range || ostack.last.sym == :exclusive_range)
          @out.value(nil)
        end
        # Handle keyword argument shorthand: if last token was : in a hash (e.g., {a:}),
        # push nil as placeholder - treeoutput will convert {a:} to {a: a}
        if !ostack.empty? && ostack.first && ostack.first.sym == :hash &&
           src.lasttoken && src.lasttoken[0] == ":" &&
           ostack.last.sym == :ternalt
          @out.value(nil)
        end
        # Handle keyword argument shorthand in function calls: foo(a:)
        # Similar to above but for parenthesis context (ostack.first.sym == nil)
        if !ostack.empty? && ostack.first && ostack.first.sym == nil &&
           src.lasttoken && src.lasttoken[0] == ":" &&
           ostack.last && ostack.last.sym == :ternalt
          @out.value(nil)
        end
        src.unget(token) if !lp_on_entry
        reduce(ostack, op)
        return :break
      elsif op && op.type == :lp
        reduce(ostack, op)
        # Handling function calls and a[1] vs [1]
        #
        # - "foo[1]" (no space) → always foo.[](1) (indexing)
        # - "foo [1]" (with space) → depends on context:
        #   - If foo is result of method call (obj.method), then method([1]) (argument)
        #   - Otherwise foo.[](1) (indexing)
        #
        # Check if [ with whitespace after a method call should be an argument
        treat_as_argument = false
        if op.sym == :array && @had_ws_before_this_token && possible_func
          last_val = @out.vstack.last
          is_method_call = last_val.is_a?(Array) && (last_val[0] == :callm || last_val[0] == :safe_callm)
          # If it's "obj.method []" with space, treat [] as argument, not indexing
          if is_method_call
            treat_as_argument = true
            should_index = false
          else
            should_index = true
          end
        else
          should_index = possible_func
        end

        opstate = shunt_subexpr([op], src, should_index)
        if treat_as_argument
          # Push @opcall2 to make this a method call with the array as argument
          ostack << @opcall2
        elsif should_index
          ostack << (op.sym == :array ? Operators["#index#"] : @opcall)
        end

        reduce(@ostack, @opcall2) if @ostack[-1].nil? || @ostack[-1].sym != :call
      elsif op
        reduce(ostack, op)
        opstate = :prefix
        @ostack << op
      end
      opstate
    end

    def shunt(src)
      ostack = @ostack
      possible_func = false     # was the last token a possible function name?
      opstate = :prefix         # IF we get a single arity operator right now, it is a prefix operator
                                # "opstate" is used to handle things like pre-increment and post-increment that
                                # share the same token.
      lp_on_entry = ostack.first && ostack.first.type == :lp
      had_newline_after_ws = false  # Track if src.ws consumed a newline

      lastlp = true
      op = nil
      token = nil
      src.each do |t,o,keyword|
        op = o
        token = t
        # Save whitespace state at start of iteration - this tells us if there was
        # whitespace before THIS token (not after the previous one)
        @had_ws_before_this_token = @tokenizer.had_ws_before_token

        # Inside () parentheses, newlines act as statement separators
        # Insert implicit ; when we see a new token after a newline
        # This must happen BEFORE processing the current token
        # BUT: don't insert ; before closing paren - there's nothing after it
        is_closing_paren = op && (op.is_a?(Hash) ? (op[:infix_or_postfix] && op[:infix_or_postfix].type == :rp) : op.type == :rp)
        newline_before = @tokenizer.newline_before_current || had_newline_after_ws
        if lp_on_entry && opstate == :infix_or_postfix && newline_before && !is_closing_paren
          is_paren = ostack.first && ostack.first.sym == nil && ostack.first.type == :lp
          if is_paren
            # Insert implicit ; operator to separate statements
            do_op = Operators[";"]
            reduce(ostack, do_op)
            ostack << do_op
            opstate = :prefix  # After ; we expect a new expression
            possible_func = false  # Prevent next token from being treated as function argument
          end
        end
        # Normally we stop when encountering a keyword, but it's ok to encounter
        # one as the second operand for an infix operator.
        # Also, keywords that have operator mappings (like if/while/rescue) should
        # be treated as operators, not as keywords that stop parsing.
        # However, we need to check that the operator mapping exists for the current opstate.
        # Additionally, keywords can appear as expressions inside parentheses (e.g., "(def foo; end; 42)")
        has_op_for_state = op && (op.is_a?(Hash) ? op[opstate] : true)
        # in_parens is true for any left-paren context: (), [], {}
        # This allows ; as :do operator inside these contexts
        in_parens = lp_on_entry && ostack.first && ostack.first.type == :lp
        # Don't inhibit inside parentheses - allows ; as :do operator in (x = 1; y = 2)
        # Only inhibit if this is an operator (o is non-nil), not a value
        if (@inhibit.include?(token) && !in_parens && op) or
          keyword && !has_op_for_state &&
          !in_parens &&
          (opstate != :prefix ||
           !ostack.last ||
           ostack.last.type != :infix ||
           token == :end)

          src.unget(token)
          # If we're in prefix position with a minarity 0 operator, it needs a value
          # This handles cases like "literal("(") or return\n" where return has no argument
          # For bare splat in patterns (in *;), push :_ instead of nil
          if opstate == :prefix && ostack.last && ostack.last.type == :prefix && ostack.last.minarity == 0
            if ostack.last.sym == :splat
              @out.value(:_)
            else
              @out.value(nil)
            end
          # Special case: bare splat followed by inhibited token (in *; or in * \n)
          # Check if last token was * and splat operator is on stack
          elsif opstate == :prefix && ostack.last && ostack.last.sym == :splat &&
                src.lasttoken && src.lasttoken[0] == "*"
            @out.value(:_)
            opstate = :infix_or_postfix  # Mark that we provided a value
          end
          break
        end

        if op
          op = op[opstate] if op.is_a?(Hash)

          # Handle prefix operators with minarity 0 when an infix operator arrives
          # Example: "break; 42" - the ; is infix, so break should close with nil
          # For bare splat in patterns, push :_ instead of nil
          # Note: :lp types ([, {, () are not infix - they provide values to the prefix operator
          if opstate == :prefix && op && op.type == :infix && ostack.last && ostack.last.type == :prefix && ostack.last.minarity == 0
            if ostack.last.sym == :splat
              @out.value(:_)
            else
              @out.value(nil)
            end
          end

          # This makes me feel dirty, but it reflects the grammar:
          # - Inside a literal hash, or function call arguments "," outside of any type of parentheses binds looser than a function call,
          #   while outside of it, it binds tighter... Yay for context sensitive precedence rules.
          # This whole module needs a cleanup
          op = Operators["#,#"] if op == Operators[","] and lp_on_entry

          r = oper(src,token,ostack, opstate, op, lp_on_entry, possible_func, lastlp)
          if r == :break
            break
          else
            opstate = r
          end
        else
          # Check if this is a statement-level keyword that needs special parsing
          # These keywords can appear as expressions (e.g., "a = while true; break; end")
          # Note: unless, until, begin, and lambda are now handled as operators, not in this special case
          if keyword && [:for, :def].include?(token)
            # Unget the keyword and call the appropriate parser method
            src.unget(token)
            parser_method = case token
              when :for then :parse_for
              when :def then :parse_def
            end
            result = @parser.send(parser_method)
            @out.value(result)
          else
            # When a value follows a possible function name without a newline,
            # treat it as an argument. But if there was a newline, it's a new statement.
            # This ensures "foo bar" is "foo(bar)" but "foo\nbar" is two separate expressions.
            if possible_func && !@tokenizer.newline_before_current
              # Fix for parser bug with parenthesis-free method chains like "result.should eql 3"
              # Reduce operators with priority > @opcall2 (9), but not @opcall2 itself
              # This makes "foo bar baz" parse as "foo(bar(baz))" not "foo(bar, baz)"
              # while also properly handling single arguments like "x.y 42"
              reduce(ostack, @opcall2)
              ostack << @opcall2
            end
            @out.value(token)
          end
          opstate = :infix_or_postfix # After a non-operator value, any single arity operator would be either postfix,
                                      # so when seeing the next operator we will assume it is either infix or postfix.
        end
        possible_func = op ? op.type == :lp :  (!token.is_a?(Numeric) || !token.is_a?(Array))
        lastlp = false
        if lp_on_entry
          src.ws
          # Track if ws() consumed a newline for next token's implicit semicolon check
          had_newline_after_ws = @tokenizer.last_ws_consumed_newline
        else
          had_newline_after_ws = false
        end
      end

      if opstate == :prefix && (ostack.size && ostack.last && ostack.last.type == :prefix)
        # This is an error unless the top of the @ostack has minarity == 0,
        # which means it's ok for it to be provided with no argument
        # HOWEVER: respect operator precedence. If the incoming operator has
        # higher precedence (higher priority number), let it be reduced first.
        # Example: "break *[1, 2]" - we DON'T close break with nil yet
        if ostack.last.minarity == 0
          # Only push nil if there's an incoming operator with lower precedence
          # Don't push nil at end of input (op=nil) - the operator should have its value
          if op && op.pri < ostack.last.pri
            # Incoming operator has lower precedence (lower priority number) - don't close yet
            # Example: "break *[1, 2]" - splat (pri 8) < break (pri 22), so process splat first
          elsif op
            @out.value(nil)
          end
          # At end of input (op=nil), don't push nil - operator should reduce with its value
        else
          scanner = @tokenizer.scanner
          token_info = token.respond_to?(:position) ? token.position.short : token.inspect
          # Include ostack and vstack state for debugging
          vstack_info = @out.vstack
          msg = "Missing value for prefix operator #{ostack[-1].sym.to_s} / token: #{token_info} / ostack: #{ostack.inspect} / vstack: #{vstack_info.inspect}"
          raise ShuntingYardError.new(msg,
                                      scanner ? scanner.filename : nil,
                                      scanner ? scanner.lineno : nil,
                                      scanner ? scanner.col : nil)
        end
      end

      reduce(@ostack)
      return @out if @ostack.empty?
      scanner = @tokenizer.scanner
      msg = "Syntax error. #{@ostack.inspect}"
      raise ShuntingYardError.new(msg,
                                  scanner ? scanner.filename : nil,
                                  scanner ? scanner.lineno : nil,
                                  scanner ? scanner.col : nil)
    end

    def parse(inhibit=[])
      out = @out.dup
      out.reset
      tmp = self.class.new(out, @tokenizer, @parser, inhibit)
      res = tmp.shunt(@tokenizer)
      res ? res.result : nil
    end
  end

  def self.parser(scanner, parser)
     ShuntingYard.new(TreeOutput.new,Tokens::Tokenizer.new(scanner,parser), parser)
  end

end
