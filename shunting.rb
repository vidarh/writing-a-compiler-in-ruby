
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
             # Don't reduce prefix operators when a higher-precedence prefix operator follows
             !(ostack.last.type == :prefix && op && op.type == :prefix && pri < ostack.last.pri)
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
        elsif op.sym == :rescue_mod && ostack.length == 0
          #STDERR.puts "   rescue clause (not modifier)"
          # Unlike if/while, rescue in prefix position signals end of begin block body
          # Only break if ostack is empty (we're at statement level)
          # Otherwise, parse as expression
          src.unget(token)
          reduce(ostack)
          return :break
        elsif op.sym == :begin_stmt
          #STDERR.puts "   begin statement"
          @out.value(@parser.parse_begin_body)
          return :prefix
        elsif op.sym == :lambda_stmt
          #STDERR.puts "   lambda statement"
          # Lambda keyword already consumed, just parse the block
          @parser.ws
          block = @parser.parse_block or @parser.expected("do .. end block")
          # Build lambda node: [:lambda, args, body, rescue, ensure]
          result = Parser::E[@parser.position, :lambda, *block[1..-1]]
          @out.value(result)
          return :prefix
        end
      end

      if op.sym == :hash_or_block || op.sym == :block
        # Don't treat { as block argument if there was a newline before current token
        # This fixes: -> { x }.a \n lambda { y } where lambda should NOT be block arg to .a
        if (possible_func || (@ostack.last && @ostack.last.sym == :call) || @ostack.last == @opcallm) && !@tokenizer.newline_before_current
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
      elsif op.sym == :quoted_exp
        @out.value(parse_quoted_exp)
      elsif op.type == :rp
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
        # Handle endless ranges: if the last token was .. or ... (range operator) followed immediately by ),
        # push nil as the missing right-hand value
        if !ostack.empty? && ostack.first && ostack.first.sym == nil &&
           src.lasttoken && (src.lasttoken[0] == ".." || src.lasttoken[0] == "...") &&
           (ostack.last.sym == :range || ostack.last.sym == :exclusive_range)
          @out.value(nil)
        end
        src.unget(token) if !lp_on_entry
        reduce(ostack, op)
        return :break
      elsif op.type == :lp
        reduce(ostack, op)
        opstate = shunt_subexpr([op], src, possible_func)
        ostack << (op.sym == :array ? Operators["#index#"] : @opcall) if possible_func

        # Handling function calls and a[1] vs [1]
        #
        # - If foo is a method, then "foo [1]" is "foo([1])"
        # - If foo is a local variable, then "foo [1]" is "foo.[](1)"
        # - foo[1] is always foo.[](1)
        # So we need to know if there's whitespace, and we then higher up need to know if
        # if's a method. Fuck the Ruby grammar
        reduce(@ostack, @opcall2) if @ostack[-1].nil? || @ostack[-1].sym != :call
      else
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

      lastlp = true
      op = nil
      token = nil
      src.each do |t,o,keyword|
        op = o
        token = t

        # Normally we stop when encountering a keyword, but it's ok to encounter
        # one as the second operand for an infix operator.
        # Also, keywords that have operator mappings (like if/while/rescue) should
        # be treated as operators, not as keywords that stop parsing.
        # However, we need to check that the operator mapping exists for the current opstate.
        # Additionally, keywords can appear as expressions inside parentheses (e.g., "(def foo; end; 42)")
        has_op_for_state = op && (op.is_a?(Hash) ? op[opstate] : true)
        in_parens = lp_on_entry && ostack.first && ostack.first.type == :lp && ostack.first.sym == nil
        if @inhibit.include?(token) or
          keyword && !has_op_for_state &&
          !in_parens &&
          (opstate != :prefix ||
           !ostack.last ||
           ostack.last.type != :infix ||
           token == :end)

          src.unget(token)
          break
        end

        if op
          op = op[opstate] if op.is_a?(Hash)

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
            if possible_func
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
        src.ws if lp_on_entry
      end

      if opstate == :prefix && (ostack.size && ostack.last && ostack.last.type == :prefix)
        # This is an error unless the top of the @ostack has minarity == 0,
        # which means it's ok for it to be provided with no argument
        # HOWEVER: respect operator precedence. If the incoming operator has
        # higher precedence (lower priority number), let it be reduced first.
        # Example: "break *[1, 2]" - * (pri 8) should be reduced before break (pri 22)
        if ostack.last.minarity == 0
          # Only close with nil if incoming operator has lower/equal precedence
          if op && op.pri < ostack.last.pri
            # Incoming operator has higher precedence - don't close yet
          else
            @out.value(nil)
          end
        else
          scanner = @tokenizer.scanner
          token_info = token.respond_to?(:position) ? token.position.short : token.inspect
          # Include ostack and vstack state for debugging
          vstack_info = @out.instance_variable_get(:@vstack) rescue []
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
      tmp = self.class.new(out, @tokenizer,@parser, inhibit)
      res = tmp.shunt(@tokenizer)
      res ? res.result : nil
    end
  end

  def self.parser(scanner, parser)
     ShuntingYard.new(TreeOutput.new,Tokens::Tokenizer.new(scanner,parser), parser)
  end

end
