
require 'pp'
require 'treeoutput'

# FIXME:
#
# Handle symbols that are valid operators but that are not valid in certain circumstances:
#  '}' should cause a return if no '{' has been seen, and should be unget.
#  ',' should cause a return if :call isn't on the opstack?

module OpPrec
  class ShuntingYard
    def initialize output,tokenizer, parser
      @ostack,@out,@tokenizer,@parser = [],output,tokenizer,parser
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

    def parse_block start
      @parser.parse_block(start)
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

          if op.sym == :hash_or_block || op.sym == :block
            if possible_func || @ostack[-1] == Operators["#call#"] || @ostack[-1] == Operators["#callm#"]
              @out.value([]) if @ostack[-1] != Operators["#call#"]
              @out.value(parse_block(token))
              @out.oper(Operators["#flatten#"])
              @ostack << Operators["#call#"]  if @ostack[-1] != Operators["#call#"]
            elsif op.sym == :hash_or_block
              op = Operators["#hash#"]
            else
              raise "Block not allowed here"
            end
          else
            reduce(op)
            if op.type != :rp
              opstate = :prefix
              @ostack << (op.type == :lp && possible_func ? Operators["#call#"] : op)
            end
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

  def self.parser scanner, parser
     ShuntingYard.new(TreeOutput.new,Tokens::Tokenizer.new(scanner), parser)
  end

end
