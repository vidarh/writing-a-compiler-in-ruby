
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
end
