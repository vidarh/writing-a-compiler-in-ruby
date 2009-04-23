
module OpPrec

  class TreeOutput
    def initialize
      reset
    end

    @@dont_rewrite = false
    def self.dont_rewrite
      @@dont_rewrite = true
    end

    def reset
      @vstack = []
    end

    def flatten(r)
      return r if !r.is_a?(Array)
      return r if r[0] != :comma
      return r[1..2] if !r[2].is_a?(Array) or r[2][0] == :array
      return [r[1], flatten(r[2])] if r[2][0] != :comma
      return [r[1]] + flatten(r[2])
    end

    def oper(o)
      raise "Missing value in expression / #{o.inspect}" if @vstack.empty? && o.minarity > 0
      rightv = @vstack.pop if o.arity > 0

      raise "Missing value in expression / op: #{o.inspect} / vstack: #{@vstack.inspect} / rightv: #{rightv.inspect}" if @vstack.empty? and o.minarity > 1
      leftv = @vstack.pop if o.arity > 1

      leftv = [] if !leftv && o.sym == :flatten # Empty argument list. :flatten is badly named

      la = leftv.is_a?(Array)
      ra = rightv.is_a?(Array)


      # Debug option: Output the tree without rewriting.
      return @vstack << [o.sym, leftv, rightv] if @@dont_rewrite

      # Rewrite rules to simplify the tree
      if ra and rightv[0] == :flatten
        @vstack << [o.sym, leftv] + flatten(rightv[1..-1])
      elsif ra and rightv[0] == :call and o.sym == :callm
        @vstack << [o.sym, leftv] + flatten(rightv[1..-1])
      elsif la and leftv[0] == :callm and o.sym == :call
        @vstack << leftv + [flatten(rightv)]
      elsif la and leftv[0] == :callm and o.sym == :assign and leftv[2] == :[]
        # FIXME: Will need rewrite for things like self.foo = bar too, but in that case *without
        # arguments
        rightv = [rightv] if !ra
        @vstack << [:callm, leftv[1], "[]=".to_sym,leftv[3]+rightv]
      elsif o.sym == :index
        if ra and rightv[0] == :array
          @vstack << [:callm, leftv, :[], flatten(rightv[1..-1])]
        else
          @vstack << [:callm, leftv, :[], [rightv]]
        end
      elsif ra and rightv[0] == :comma and o.sym == :array || o.sym == :hash
        @vstack << [o.sym, leftv].compact + flatten(rightv)
      elsif ra and rightv[0] == :comma and o.sym != :comma
        @vstack << [o.sym, leftv, flatten(rightv)].compact
      else
        @vstack << [o.sym, flatten(leftv), rightv].compact
      end
      return
    end

    def value(v)
      @vstack << v
    end

    def result
      raise "Incomplete expression - #{@vstack.inspect}" if @vstack.length > 1
      return @vstack[0]
    end
  end
end
