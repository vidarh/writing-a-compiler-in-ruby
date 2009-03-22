
require 'pp'

module OpPrec

  class TreeOutput
    def initialize
      reset
    end

    def reset
      @vstack = []
    end

    def flatten r
      return r if !r.is_a?(Array)
      return r if r[0] != :comma
      return [r[1],flatten(r[2])]
    end

    def oper o
      raise "Missing value in expression / #{o.inspect}" if @vstack.empty? && o.minarity > 0
      rightv = @vstack.pop if o.arity > 0
      raise "Missing value in expression / #{o.inspect} / #{@vstack.inspect} / #{rightv.inspect}" if @vstack.empty? and o.minarity > 1
      leftv = @vstack.pop if o.arity > 1

      la = leftv.is_a?(Array)
      ra = rightv.is_a?(Array)

      # Flatten :callm nodes
      if la && leftv[0] == :callm && o.sym == :call
        @vstack << leftv + [flatten(rightv)]
        return
      end

      if ra && rightv[0] == :comma
        # This is a way to flatten the tree by removing all the :comma operators
        if o.sym == :call
          @vstack << [o.sym,leftv,rightv[1..-1]].compact
        else
          @vstack << [o.sym,leftv].compact + rightv[1..-1]
        end
      else # no comma operator
        @vstack << [o.sym, leftv, rightv].compact
      end
    end

    def value v; @vstack << v; end

    def result
      raise "Incomplete expression - #{@vstack.inspect}" if @vstack.length > 1
      return @vstack[0]
    end
  end

  class ShuntingYard
    def initialize output,tokenizer
      @ostack,@out,@tokenizer = [],output,tokenizer
    end

    def reset
      @ostack = []
      @out.reset
    end
    
    def reduce op = nil
      pri = op ? op.pri : 0
      # We check for :postfix to handle cases where a postfix operator has been given a lower precedence than an
      # infix operator, yet it needs to bind tighter to tokens preceeding it than a following infix operator regardless,
      # because the alternative gives a malfored expression.
      while  !@ostack.empty? && (@ostack[-1].pri > pri || @ostack[-1].type == :postfix)
        o = @ostack.pop
        @out.oper(o) if o.sym
        return if o.type == :lp 
      end
    end
    
    def shunt src
      possible_func = false     # was the last token a possible function name?
      opstate = :prefix         # IF we get a single arity operator right now, it is a prefix operator
                                # "opstate" is used to handle things like pre-increment and post-increment that
                                # share the same token.
      lastlp = false            # Was the last token a :lp? Used to output "dummy values" for empty parentheses
      src.each do |token,op|
        if op
          # Handling "a[1]" differently from "[1]"
          op = Operators["#index#"] if op.sym == :createarray && possible_func
          op = op[opstate] if op.is_a?(Hash)
          @out.value(nil) if op.type == :rp && lastlp # Dummy value to balance out the expressions when closing an empty pair of parentheses.
          reduce(op)
          if op.type != :rp
            opstate = :prefix
            @ostack << (op.type == :lp && possible_func ? Operators["#call#"] : op)
            o = @ostack[-1]
          end
        else 
          if possible_func
            reduce
            @ostack << Operators["#call#"]
          end
          @out.value(token)
          opstate = :infix_or_postfix # After a non-operator value, any single arity operator would be either postfix,
                                      # so when seeing the next operator we will assume it is either infix or postfix.
        end
        possible_func = !op && !token.is_a?(Numeric)
        lastlp = op && op.type == :lp
      end

      if opstate == :prefix && @ostack.size && @ostack[-1] && @ostack[-1].type == :prefix
        # This is an error unless the top of the @ostack has minarity == 0,
        # which means it's ok for it to be provided with no argument
        if @ostack[-1].minarity == 0
          @out.value(nil)
        else
          raise "Missing value for prefix operator #{@ostack[-1].sym.to_s}"
        end
      end

      reduce
      return @out if  @ostack.empty?
      raise "Syntax error. #{@ostack.inspect}"
    end
    
    def parse
      reset
      shunt(@tokenizer).result
    end
  end

  def self.parser scanner
     ShuntingYard.new(TreeOutput.new,Tokens::Tokenizer.new(scanner))
  end

end
