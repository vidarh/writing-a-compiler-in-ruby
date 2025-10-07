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

    def oper_incr(la, leftv, ra, rightv)
        # FIXME: This probably doesn't belong here, but rather in transform.rb
        #
        # :incr represents +=. There is an added complication: If the left hand side is
        # the result of a foo[bar] array index operation, foo[bar] += baz needs to be translated to
        # foo.[]=(bar, foo[bar] + 1) (that's the clean version, see below for the dirty details)
        #
        if ra and rightv[0] == :array
          r = flatten(rightv[1..-1])
        else
          r = [rightv]
        end
        if la and leftv[0] == :callm and leftv[2] == :[]
          #
          # Ruby Array syntax and += etc. is all syntactic sugar:
          #
          # foo[bar] += baz
          #
          # =>
          #
          # __incr = bar
          # foo.[]=(__incr, foo[__incr] + baz)
          #
          # =>
          #
          # __incr = bar
          # foo.[]=(__incr, foo.+(foo.[](__incr),baz)
          #
          # =>
          #
          lexp = [:callm, leftv[1], :[], :__incr]
          @vstack << E[:let, [:__incr], [:do,
                                         E[:assign, :__incr, leftv[3][0]],
                                         E[:callm, leftv[1], :[]=, [:__incr, [:callm, lexp, :"+", r]]]
                                        ]
                      ]
        else
          @vstack << E[:assign, leftv, [:callm, leftv, :"+", r]]
        end
    end

    def oper_call_right(leftv, o, rightv)
      s = rightv[1]
      r = rightv[2..-1]
      block = r[1]
      args = r[0]
      if args.is_a?(Array) && args[0] == :callm
        args = E[args]
      end
      expr = E[o.sym,leftv,s]

      if args || block
        args ||= []
        expr << Array(args)
      end
      expr << block if block
      @vstack << expr
    end

    def oper(o)
      raise "Missing value in expression / #{o.inspect}" if @vstack.empty? && o.minarity > 0
      rightv = @vstack.pop if o.arity > 0

      raise "Missing value in expression / op: #{o.inspect} / vstack: #{@vstack.inspect} / rightv: #{rightv.inspect}" if @vstack.empty? and o.minarity > 1
      leftv = nil
      leftv = @vstack.pop if o.arity > 1

      leftv = E[] if !leftv && o.sym == :flatten # Empty argument list. :flatten is badly named

      la = leftv.is_a?(Array)
      ra = rightv.is_a?(Array)


      # Debug option: Output the tree without rewriting.
      return @vstack << E[o.sym, leftv, rightv] if @@dont_rewrite

      # Rewrite rules to simplify the tree
      if ra and rightv[0] == :call and o.sym == :callm
        oper_call_right(leftv, o, rightv)
      elsif la and leftv[0] == :callm and o.sym == :call
        block = ra && rightv[0] == :flatten && rightv[2].is_a?(Array) && (rightv[2][0] == :proc || rightv[2][0] == :block)
        comma = ra && rightv[0] == :comma
        # FIXME: @bug - the following evaluates to false in compiler
        # but not yet been able to reproduce exact conditions.
        #args = comma || block ? flatten(rightv) : rightv
        args = comma
        if !args
          if block
            args = flatten(rightv)
          else
            args = rightv
          end
        end

        args = E[args] if !comma && !block && args.is_a?(Array)
        args = E[args]
        if block
          @vstack << leftv.concat(*args)
        else
          @vstack << leftv + args
        end
      elsif la and leftv[0] == :callm and o.sym == :assign
        rightv = E[rightv]
        lv = leftv[3]
        lv = [lv] if lv && !lv.is_a?(Array)
        # FIXME: Workaround for compiler @bug: Putting the above as a ternary if causes selftest-c target to fail.
        if lv
          args = lv + rightv
        else
          args = rightv
        end

        # FIXME: For some reason "eq" gets mis-identified as method call.
        eq = "#{leftv[2].to_s}="
        args = E[args] if args[0] == :callm
        @vstack << E[:callm, leftv[1], eq.to_sym,args]
      elsif o.sym == :index
        if ra and rightv[0] == :array
          @vstack << E[:callm, leftv, :[], flatten(rightv[1..-1])]
        else
          @vstack << E[:callm, leftv, :[], [rightv]]
        end
      elsif o.sym == :incr
        oper_incr(la,leftv,ra,rightv)
      elsif ra and rightv[0] == :comma and o.sym == :array || o.sym == :hash
        @vstack << E[o.sym, leftv].compact + flatten(rightv)
      elsif ra and rightv[0] == :comma and o.sym == :return
        @vstack << E[o.sym, leftv, [:array]+flatten(rightv)].compact
      elsif ra and rightv[0] == :comma and o.sym != :comma
        @vstack << E[o.sym, leftv, flatten(rightv)].compact
      elsif ra and rightv[0] == :flatten
        # Convert [:call, :lambda, [], [:proc, ...]] to [:lambda, ...]
        # This allows lambda to work like a method call while generating proper lambda nodes
        if o.sym == :call && leftv == :lambda && rightv[2].is_a?(Array) && rightv[2][0] == :proc
          proc_node = rightv[2]
          @vstack << E[:lambda, proc_node[1], proc_node[2]]
        else
          @vstack << E[o.sym, leftv] + flatten(rightv[1..-1])
        end
      else
        # FIXME This seemingly fixes issue where single argument function call does not get its arguments wrapped.
        # FIXME Need to verify that this doesn't fail any other tests than the ones it should
        # FIXME: rightv[0] there becomes bitfield access if rightv contains an integer,
        # which it sometimes does. These work, since Fixnum#[] returns 0 or 1, and
        # 0 or 1 never matches :flatten or :comma, but it's not very satisfying code

        #STDERR.puts "o=#{o.inspect} rightv=#{rightv.inspect} leftv=#{leftv.inspect}"
        if o.sym == :call || o.sym == :callm and
          o.type == :prefix and
          rightv && (!ra || rightv[0] != :flatten) and
          (!ra || rightv[0] != :comma)
          rightv = E[rightv]
        end
        lv = flatten(leftv)
        if o.sym == :assign && lv.is_a?(Array)
            lv = [:destruct] + lv
        end

        @vstack << E[o.sym, lv, rightv].compact
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
