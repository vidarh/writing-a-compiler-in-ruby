
require 'pp'
require 'treeoutput'

require 'tokenizeradapter'

module OpPrec
  class ShuntingYard
    def initialize(output, tokenizer, parser, inhibit = [])
      @out = output

      # FIXME: Pass this in instead of storing it.
      @tokenizer = TokenizerAdapter.new(tokenizer,parser)
      @parser = parser
      
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

      while  !ostack.empty? && (ostack.last.pri > pri || (ostack.last.pri == pri && op.assoc == :left) || ostack.last.type == :postfix) && ((op && op.type == :rp) || ostack.last.type != :lp)
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

    def shunt_subexpr(ostack, src)
      old = @ostack
      @ostack = ostack
      shunt(src)
      @ostack = old
      :infix_or_postfix
    end
    
    def oper(src,token,ostack, opstate, op, lp_on_entry, possible_func, lastlp)

      if op.sym == :hash_or_block || op.sym == :block
        if possible_func || (@ostack.last && @ostack.last.sym == :call) || @ostack.last == @opcallm
          ocall = @ostack.last ? @ostack.last.sym == :call : false
          @out.value([]) if !ocall
          @out.value(parse_block(token))
          @out.oper(Operators["#flatten#"])
          ostack << @opcall if !ocall
        elsif op.sym == :hash_or_block
          opstate = shunt_subexpr([Operators["#hash#"]],src)
        else
          raise "Block not allowed here"
        end
      elsif op.sym == :quoted_exp
        @out.value(parse_quoted_exp)
      elsif op.type == :rp
        @out.value(nil) if lastlp
        @out.value(nil) if src.lasttoken and src.lasttoken[1] == Operators[","]
        src.unget(token) if !lp_on_entry
        reduce(ostack, op)
        return :break
      elsif op.type == :lp
        reduce(ostack, op)
        opstate = shunt_subexpr([op],src)
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
        # FIXME: @bug This is a workaround for a bug in find_vars that doesn't correctly
        # identify variables used in methods calls.
        # It appears it might also cause the env allocated for the
        # block to not be correctly initialized.
        ostack
        opstate

        # Normally we stop when encountering a keyword, but it's ok to encounter
        # one as the second operand for an infix operator
        if @inhibit.include?(token) or
          keyword &&
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
          if possible_func
            reduce(ostack)
            ostack << @opcall2
          end
          @out.value(token)
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
        if ostack.last.minarity == 0
          @out.value(nil)
        else
          raise "Missing value for prefix operator #{ostack[-1].sym.to_s}"
        end
      end

      reduce(@ostack)
      return @out if @ostack.empty?
      raise "Syntax error. #{@ostack.inspect}"
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
