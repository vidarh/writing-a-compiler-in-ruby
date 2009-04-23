
require 'pp'
require 'treeoutput'

module OpPrec
  class ShuntingYard
    def initialize(output, tokenizer, parser)
      @out = output
      @tokenizer = tokenizer
      @parser = parser
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
      while  !ostack.empty? && (ostack.last.pri > pri || ostack.last.type == :postfix) && ((op && op.type == :rp) || ostack.last.type != :lp)
        o = ostack.pop
        @out.oper(o) if o.sym
      end
    end

    def parse_block(start)
      @parser.parse_block(start)
    end

    def shunt(src, ostack = [], inhibit = [])
      possible_func = false     # was the last token a possible function name?
      opstate = :prefix         # IF we get a single arity operator right now, it is a prefix operator
                                # "opstate" is used to handle things like pre-increment and post-increment that
                                # share the same token.
      lp_on_entry = ostack.first && ostack.first.type == :lp
      opcall  = Operators["#call#"]
      opcallm = Operators["."]
      lastlp = true
      src.each do |token,op|
        if inhibit.include?(token)
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

          if op.sym == :hash_or_block || op.sym == :block
            if possible_func || ostack.last == opcall || ostack.last == opcallm
              @out.value([]) if ostack.last != opcall
              @out.value(parse_block(token))
              @out.oper(Operators["#flatten#"])
              ostack << opcall if ostack.last != opcall
            elsif op.sym == :hash_or_block
              op = Operators["#hash#"]
              shunt(src, [op])
              opstate = :infix_or_postfix
            else
              raise "Block not allowed here"
            end
          else
            if op.type == :rp
              @out.value(nil) if lastlp
              @out.value(nil) if src.lasttoken and src.lasttoken[1] == Operators[","]
              src.unget(token) if !lp_on_entry
            end
            reduce(ostack, op)
            if op.type == :lp
              shunt(src, [op])
              opstate = :infix_or_postfix
              # Handling function calls and a[1] vs [1]
              ostack << (op.sym == :array ? Operators["#index#"] : opcall) if possible_func
            elsif op.type == :rp
              break
            else
              opstate = :prefix
              ostack << op
            end
          end
        else
          if possible_func
            reduce(ostack)
            ostack << opcall
          end
          @out.value(token)
          opstate = :infix_or_postfix # After a non-operator value, any single arity operator would be either postfix,
                                      # so when seeing the next operator we will assume it is either infix or postfix.
        end
        possible_func = op ? op.type == :lp :  !token.is_a?(Numeric)
        lastlp = false
        src.ws if lp_on_entry
      end

      if opstate == :prefix && ostack.size && ostack.last && ostack.last.type == :prefix
        # This is an error unless the top of the @ostack has minarity == 0,
        # which means it's ok for it to be provided with no argument
        if ostack.last.minarity == 0
          @out.value(nil)
        else
          raise "Missing value for prefix operator #{ostack[-1].sym.to_s}"
        end
      end

      reduce(ostack)
      return @out if ostack.empty?
      raise "Syntax error. #{ostack.inspect}"
    end

    def parse(inhibit=[])
      out = @out.dup
      out.reset
      tmp = self.class.new(out, @tokenizer,@parser)
      res = tmp.shunt(@tokenizer,[],inhibit)
      res ? res.result : nil
    end
  end

  def self.parser(scanner, parser)
     ShuntingYard.new(TreeOutput.new,Tokens::Tokenizer.new(scanner), parser)
  end

end
