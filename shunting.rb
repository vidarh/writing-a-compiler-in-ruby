
require 'pp'

module OpPrec
  Oper = Struct.new(:pri,:sym,:type)

  class TreeOutput
    def initialize
      reset
    end

    def reset
      @vstack = []
    end

    def oper o
      rightv = @vstack.pop
      raise "Missing value in expression" if !rightv
      if (o.sym == :comma) && rightv.is_a?(Array) && rightv[0] == :comma
        # This is a way to flatten the tree by removing all the :comma operators
        @vstack << [o.sym,@vstack.pop] + rightv[1..-1]
      elsif (o.sym == :call) && rightv.is_a?(Array) && rightv[0] == :comma
        # This is a way to flatten the tree by removing all the :comma operators
        @vstack << [@vstack.pop] + rightv[1..-1]
      else
        if o.type == :infix
          leftv = @vstack.pop
          raise "Missing value in expression" if !leftv
          @vstack << [o.sym, leftv, rightv]
        else
          @vstack <<  [o.sym,rightv]
        end
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
        return if o.type == :lp
        @out.oper(o)
      end
    end
    
    def shunt src
      possible_func = false     # was the last token a possible function name?
      opstate = :prefix         # IF we get a single arity operator right now, it is a prefix operator
                                # "opstate" is used to handle things like pre-increment and post-increment that
                                # share the same token.
      src.each do |token|
        if op = @opers[token]
          op = op[opstate] if op.is_a?(Hash)
          if op.type == :rp then reduce
          else
            opstate = :prefix
            reduce op # For handling the postfix operators
            @ostack << (op.type == :lp && possible_func ? Oper.new(1, :call, :infix) : op)
            o = @ostack[-1]
          end
        else 
          @out.value(token)
          opstate = :infix_or_postfix # After a non-operator value, any single arity operator would be either postfix,
                                      # so when seeing the next operator we will assume it is either infix or postfix.
        end
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
    opers = {
      "," => Oper.new(2,  :comma,   :infix),
      "=" => Oper.new(6,  :assign,   :infix),
      "<" => Oper.new(9,  :lt,   :infix),
      "+" => Oper.new(10, :add,  :infix),
      "-" => Oper.new(10, :sub,  :infix),
      "!" => Oper.new(10, :not,   :prefix),
      "*" => Oper.new(20, :mul,   :infix),
      "/" => Oper.new(20, :div,   :infix),

      "[" => Oper.new(99, :index, :infix),
      "]" => Oper.new(99, nil,   :rp),

      "(" => Oper.new(99, nil,   :lp),
      ")" => Oper.new(99, nil,   :rp)
    }

    ShuntingYard.new(opers,TreeOutput.new,Tokens::Tokenizer.new(scanner))
  end

end
