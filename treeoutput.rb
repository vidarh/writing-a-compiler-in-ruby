require 'compilererror'
require 'ast'

module OpPrec

  class TreeOutput
    include AST

    attr_reader :vstack

    def initialize
      reset
    end

    def set_scanner(scanner)
      @scanner = scanner
      @filename = scanner.filename if scanner
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

    # Convert :ternalt to :pair for symbol shorthand syntax (foo: value)
    def convert_ternalt_to_pair(elem)
      if elem.is_a?(Array) && elem[0] == :ternalt
        # foo: 42 becomes [:ternalt, foo, 42] but should be [:pair, :foo, 42]
        # {a:} becomes [:ternalt, a, nil] but should be [:pair, :a, a] (keyword argument shorthand)
        # Convert symbol name to symbol literal
        key_sym = elem[1].is_a?(Symbol) ? elem[1] : elem[1].to_sym
        value = elem[2]
        # If no value provided (keyword argument shorthand), use the key name as the value
        if value.nil?
          value = elem[1]  # Use the variable name as the value
        end
        return E[:pair, E[:sexp, key_sym.inspect.to_sym], value]
      end
      elem
    end

    # Group consecutive :pair and :ternalt elements into a :hash
    # Used to handle implicit hashes in arrays like ["foo" => :bar] and [foo: 42]
    # :ternalt represents symbol shorthand (foo: value) which should become (:pair :foo value)
    def group_pairs(elements)
      result = []
      pairs = []

      elements.each do |elem|
        elem = convert_ternalt_to_pair(elem)
        if elem.is_a?(Array) && elem[0] == :pair
          pairs << elem
        else
          # Non-pair element - flush any accumulated pairs as a hash
          if !pairs.empty?
            result << E[:hash] + pairs
            pairs = []
          end
          result << elem
        end
      end

      # Flush remaining pairs
      if !pairs.empty?
        result << E[:hash] + pairs
      end

      result
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
      if @vstack.empty? && o.minarity > 0
        msg = "Missing value in expression / #{o.inspect}"
        raise ShuntingYardError.new(msg, @filename, @scanner ? @scanner.lineno : nil, @scanner ? @scanner.col : nil)
      end
      rightv = @vstack.pop if o.arity > 0

      if @vstack.empty? and o.minarity > 1
        msg = "Missing value in expression / op: #{o.inspect} / vstack: #{@vstack.inspect} / rightv: #{rightv.inspect}"
        raise ShuntingYardError.new(msg, @filename, @scanner ? @scanner.lineno : nil, @scanner ? @scanner.col : nil)
      end

      leftv = nil
      leftv = @vstack.pop if o.arity > 1

      leftv = E[] if !leftv && o.sym == :flatten # Empty argument list. :flatten is badly named

      la = leftv.is_a?(Array)
      ra = rightv.is_a?(Array)


      # Debug option: Output the tree without rewriting.
      return @vstack << E[o.sym, leftv, rightv] if @@dont_rewrite

      if o.sym == :if_mod
        o = Oper.new(2, :if, :prefix, 1, 0)
        l = rightv
        rightv = leftv
        leftv  = l
      elsif o.sym == :unless_mod
        o = Oper.new(2, :unless, :prefix, 1, 0)
        l = rightv
        rightv = leftv
        leftv  = l
      end

      if o.sym == :while_mod
        o = Oper.new(2, :while, :prefix, 1, 0)
        l = rightv
        rightv = leftv
        leftv  = l
      elsif o.sym == :until_mod
        o = Oper.new(2, :until, :prefix, 1, 0)
        l = rightv
        rightv = leftv
        leftv  = l
      end

      if o.sym == :rescue_mod
        o = Oper.new(2, :rescue, :prefix, 1, 0)
        l = rightv
        rightv = leftv
        leftv  = l
      end

      # Rewrite rules to simplify the tree
      if ra and rightv[0] == :call and o.sym == :callm
        oper_call_right(leftv, o, rightv)
      elsif la and leftv[0] == :callm and o.sym == :call
        block = ra && rightv[0] == :flatten && rightv[2].is_a?(Array) && (rightv[2][0] == :proc || rightv[2][0] == :block)
        to_block = ra && rightv[0] == :to_block
        comma = ra && rightv[0] == :comma
        # FIXME: @bug - the following evaluates to false in compiler
        # but not yet been able to reproduce exact conditions.
        #args = comma || block ? flatten(rightv) : rightv
        args = comma
        if !args
          if block
            args = flatten(rightv)
          elsif to_block
            # &block parameter forwarding: [:to_block, block_var]
            # Wrap it in an array to be added as the last argument
            args = E[rightv]
          else
            args = rightv
          end
        end

        args = E[args] if !comma && !block && !to_block && args.is_a?(Array)
        args = E[args]
        if block || to_block
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
        if o.sym == :array
          # Group any implicit hash pairs in the array
          elements = E[leftv].compact + flatten(rightv)
          @vstack << E[:array] + group_pairs(elements)
        else
          # Convert :ternalt to :pair for symbol shorthand in hashes
          elements = E[leftv].compact + flatten(rightv)
          elements = elements.map { |e| convert_ternalt_to_pair(e) }
          @vstack << E[o.sym] + elements
        end
      elsif o.sym == :splat && ra && rightv[0] == :comma
        # FIXME: Workaround for operator precedence issue where *a, b parses as [:splat, [:comma, a, b]]
        # instead of [:comma, [:splat, a], b]. Rewrite to correct form.
        # This extracts the first element from the comma, wraps it in splat, then rebuilds the comma.
        flat = flatten(rightv)
        first = flat[0]
        rest = flat[1..-1]
        if rest.empty?
          @vstack << E[:splat, first]
        else
          result = E[:comma, E[:splat, first], rest[0]]
          rest[1..-1].each {|r| result = E[:comma, result, r]}
          @vstack << result
        end
      elsif ra and rightv[0] == :comma and o.sym == :return
        @vstack << E[o.sym, leftv, [:array]+flatten(rightv)].compact
      elsif ra and rightv[0] == :to_block and o.sym == :comma
        # Handle comma followed by &block forwarding
        # [:comma, x, [:to_block, b]] should stay as [:comma, x, [:to_block, b]]
        @vstack << E[o.sym, leftv, rightv].compact
      elsif ra and rightv[0] == :comma and o.sym != :comma
        @vstack << E[o.sym, leftv, flatten(rightv)].compact
      elsif o.sym == :do
        # Semicolon operator - flatten nested :do blocks into single block
        # (a; b; c) becomes [:do, a, b, c] not [:do, [:do, a, b], c]
        # Handle nil values for empty statements (do; end, ;expr)
        left_exprs = leftv.nil? ? [] : (la && leftv[0] == :do ? leftv[1..-1] : [leftv])
        right_exprs = rightv.nil? ? [] : (ra && rightv[0] == :do ? rightv[1..-1] : [rightv])
        @vstack << E[:do] + left_exprs + right_exprs
      elsif ra and rightv[0] == :flatten
        # Convert [:call, :lambda, [], [:proc, ...]] to [:lambda, ...]
        # This allows lambda to work like a method call while generating proper lambda nodes
        if o.sym == :call && leftv == :lambda && rightv[2].is_a?(Array) && rightv[2][0] == :proc
          proc_node = rightv[2]
          # Preserve rescue and ensure clauses from proc node
          # proc_node is [:proc, args, exps, rescue_, ensure_body]
          @vstack << E[:lambda, proc_node[1], proc_node[2], proc_node[3], proc_node[4]]
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
            # Only wrap in :destruct if this is actually a comma-separated list of variables
            # Not if it's a single structured expression like [:deref, :Foo, :Bar]
            #
            # Known AST operator symbols that indicate a structured expression (not a variable list):
            ast_operators = [:deref, :callm, :index, :call, :sexp, :pair, :ternalt, :hash, :array]

            if ast_operators.include?(lv[0])
              # This is a structured expression like [:deref, :Foo, :Bar]
              # Don't wrap in :destruct
            else
              # This is a flattened variable list like [:a, :b, :c]
              # Wrap in :destruct for destructuring assignment
              lv = [:destruct] + lv
            end
        end

        # Handle implicit hash in array for single element or non-comma case
        if o.sym == :array
          elements = E[lv, rightv].compact
          @vstack << E[:array] + group_pairs(elements)
        elsif o.sym == :hash
          # Convert :ternalt to :pair for symbol shorthand in single-element hashes
          elements = E[lv, rightv].compact.map { |e| convert_ternalt_to_pair(e) }
          @vstack << E[:hash] + elements
        else
          # For ternalt, don't compact - nil rightv is meaningful for keyword shorthand (a:)
          if o.sym == :ternalt
            result = E[o.sym, lv, rightv]
          else
            result = E[o.sym, lv, rightv].compact
          end
          # Special handling for &block forwarding without parentheses:
          # When :to_block is created and the vstack already has a :call expression,
          # merge it into the call's arguments instead of pushing separately.
          # This handles cases like: foo m, *a, &b
          # Also handle the case where vstack has | (block parameters)
          if result.is_a?(Array) && result[0] == :to_block
            if @vstack.length > 0 && @vstack.last.is_a?(Array)
              last_op = @vstack.last[0]
              if last_op == :call || last_op == :|
                expr = @vstack.pop
                # Append to_block to the expression's arguments
                @vstack << expr + [result]
                return
              end
            end
          end
          @vstack << result
        end
      end
      return
    end

    def value(v)
      @vstack << v
    end

    def result
      if @vstack.length > 1
        # Multiple values left on stack - expression didn't reduce properly
        # This usually means: missing operator, unexpected token, or parser bug
        values_desc = @vstack.map.with_index do |v, i|
          desc = v.nil? ? "nil" : (v.is_a?(Array) && v[0].is_a?(Symbol) ? v[0].to_s : v.inspect)
          "  [#{i}]: #{desc}"
        end.join("\n")
        msg = "Expression did not reduce to single value (#{@vstack.length} values on stack)\n#{values_desc}"
        raise ShuntingYardError.new(msg, @filename, @scanner ? @scanner.lineno : nil, @scanner ? @scanner.col : nil)
      end
      return @vstack[0]
    end
  end
end
