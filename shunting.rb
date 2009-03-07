
require 'pp'

module OpPrec

  class TreeOutput
    def initialize
      reset
    end

    def reset
      @vstack = []
    end

    def oper o
      raise "Missing value in expression / #{o.inspect}" if @vstack.empty? && o.arity > 0
      rightv = @vstack.pop if o.arity > 0
      raise "Missing value in expression / #{o.inspect} / #{@vstack.inspect} / #{rightv.inspect}" if @vstack.empty? and o.arity > 1
      leftv = @vstack.pop if o.arity > 1
      # This is a way to flatten the tree by removing all the :comma operators
      if rightv.is_a?(Array) && rightv[0] == :comma
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
    def initialize opers,output,tokenizer
      @ostack,@opers,@out,@tokenizer = [],opers,output,tokenizer
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
      lastlp = false
      src.each do |token|
        # Handling "a[1]" differently from "[1]"
        token = "index" if token == "[" && possible_func
        if op = @opers[token]
          op = op[opstate] if op.is_a?(Hash)
          if op.type == :rp
            @out.value(nil) if lastlp # Dummy value to balance out the expressions when closing an empty pair of parentheses.
            reduce(op)
          else
            opstate = :prefix
            reduce op # For handling the postfix operators
            @ostack << (op.type == :lp && possible_func ? Operators["call"] : op)
            o = @ostack[-1]
          end
        else 
          @ostack << Operators["call"] if possible_func
          @out.value(token)
          opstate = :infix_or_postfix # After a non-operator value, any single arity operator would be either postfix,
                                      # so when seeing the next operator we will assume it is either infix or postfix.
        end
        lastlp = op && op.type == :lp
        possible_func = !op && !token.is_a?(Numeric)
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
     ShuntingYard.new(Operators,TreeOutput.new,Tokens::Tokenizer.new(scanner))
  end

end
