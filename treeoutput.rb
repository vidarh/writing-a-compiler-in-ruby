require 'ast'

module OpPrec

  class TreeOutput
    include AST

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
      return r if r[0] != :comma and r[0] != :flatten
      return r[1..2] if !r[2].is_a?(Array) or r[2][0] == :array
      return E[r[1], flatten(r[2])] if r[2][0] != :comma
      return E[r[1]] + flatten(r[2])
    end

    def oper(o)
      raise "Missing value in expression / #{o.inspect}" if @vstack.empty? && o.minarity > 0
      rightv = @vstack.pop if o.arity > 0

      raise "Missing value in expression / op: #{o.inspect} / vstack: #{@vstack.inspect} / rightv: #{rightv.inspect}" if @vstack.empty? and o.minarity > 1
      leftv = @vstack.pop if o.arity > 1

      leftv = E[] if !leftv && o.sym == :flatten # Empty argument list. :flatten is badly named

      la = leftv.is_a?(Array)
      ra = rightv.is_a?(Array)


      # Debug option: Output the tree without rewriting.
      return @vstack << E[o.sym, leftv, rightv] if @@dont_rewrite

      # Rewrite rules to simplify the tree
      if ra and rightv[0] == :call and o.sym == :callm
        @vstack << E[o.sym, leftv] + flatten(rightv[1..-1])
      elsif la and leftv[0] == :callm and o.sym == :call
        block = ra && rightv[0] == :flatten && rightv[2].is_a?(Array) && (rightv[2][0] == :proc || rightv[2][0] == :block)
        comma = ra && rightv[0] == :comma
        args = comma || block ? flatten(rightv) : rightv
        args = E[args] if !comma && !block && args.is_a?(Array)
        args = E[args]
        if block
          @vstack << leftv.concat(*args)
        else
          @vstack << leftv + args
        end
      elsif la and leftv[0] == :callm and o.sym == :assign
        rightv = E[rightv] if !ra
        args = leftv[3] ? leftv[3]+rightv : rightv
        eq = "#{leftv[2].to_s}="
        @vstack << E[:callm, leftv[1], eq.to_sym,args]
      elsif o.sym == :index
        if ra and rightv[0] == :array
          @vstack << E[:callm, leftv, :[], flatten(rightv[1..-1])]
        else
          @vstack << E[:callm, leftv, :[], [rightv]]
        end
      elsif o.sym == :incr
        if ra and rightv[0] == :array
          @vstack << E[:assign, leftv, [:callm, leftv, :"+", flatten(rightv[1..-1])]]
        else
          @vstack << E[:assign, leftv, [:callm, leftv, :"+", [rightv]]]
        end
      elsif ra and rightv[0] == :comma and o.sym == :array || o.sym == :hash
        @vstack << E[o.sym, leftv].compact + flatten(rightv)
      elsif ra and rightv[0] == :comma and o.sym != :comma
        @vstack << E[o.sym, leftv, flatten(rightv)].compact
      elsif ra and rightv[0] == :flatten
        @vstack << E[o.sym, leftv] + flatten(rightv[1..-1])
      else
        # FIXME This seemingly fixes issue where single argument function call does not get its arguments wrapped.
        # FIXME Need to verify that this doesn't fail any other tests than the ones it should
        if o.sym == :call || o.sym == :callm and o.type == :prefix and rightv && rightv[0] != :flatten and rightv[0] != :comma
          rightv = E[rightv]
        end
        @vstack << E[o.sym, flatten(leftv), rightv].compact
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
