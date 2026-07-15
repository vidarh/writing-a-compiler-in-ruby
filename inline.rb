
class Compiler
  # Allow `inline` keyword
  def compile_inline(*args)
    Value.new(:global, :nil)
  end

  # ---- devirt-driven method-body inlining ------------------------------------------------------------
  # When whole-program inference has proved a call `recv.m(args)` targets exactly `dclass#m`, we can splice
  # a COPY of that method's body at the call site instead of calling it. The body is written relative to
  # `self`; to transplant it we make every self-relative reference explicit on the receiver:
  #   self              -> the receiver expression
  #   an ivar `@x`      -> [:index, <receiver>, offset-of-@x-in-dclass]   (an ivar IS self[offset]; make it
  #                        receiver[offset]). Offsets come from dclass's ClassScope, so this is general --
  #                        NOT getter-specific; getters/setters are merely the trivial one-statement cases.
  #   a parameter       -> the corresponding argument expression
  # Receiver and arguments are each evaluated ONCE into a fresh temp (unless already a bare local/self/
  # literal, which is side-effect-free and substituted directly), so multiple uses in the body don't
  # re-run side effects. Returns a spliceable AST, or nil to fall back to the direct devirt call.
  def inline_devirt_body(scope, recv, args, dclass, defm)
    # Only inline inside a method/block body. At top level (main's @global_scope) a bare local used as the
    # raw-index base resolves through a path the `%s(index ...)` primitive can't load (atype "e"); those call
    # sites are rare and fall back to the direct devirt call. Method params/locals/self work fine.
    return nil if !scope_has_funcscope?(scope)
    if ENV["INLINE_DEBUG"]
      @inl_calls = (@inl_calls || 0) + 1
      STDERR.puts "[inl entry ##{@inl_calls}] #{dclass}##{defm[1]}" if @inl_calls % 200 == 1 || @inl_calls < 5
    end
    params = defm[2]
    return nil if !params.is_a?(Array) || params.any? { |p| !p.is_a?(Symbol) }   # plain positional only
    args = [] if args.nil?
    args = [args] if !args.is_a?(Array)
    return nil if args.length != params.length
    body = defm[3]                                    # compile_defm compiles this SINGLE node as the body
    return nil if body.nil?
    return nil if !inline_safe_node?(body, params)

    cscope = @classes[dclass] || @classes["Object__#{dclass}".to_sym]
    return nil if !cscope
    # Pre-resolve every ivar offset up front; bail the whole inline if any is unknown.
    offs = {}
    ok = true
    each_ivar(body) do |iv|
      o = cscope.find_ivar_offset(iv)
      if o then offs[iv] = o else ok = false end
    end
    return nil if !ok

    if ENV["INLINE_MAX"]
      @inline_dbg = (@inline_dbg || 0) + 1
      return nil if @inline_dbg > ENV["INLINE_MAX"].to_i
      STDERR.puts "[inline ##{@inline_dbg}] #{dclass}##{defm[1]} recv=#{recv.inspect[0,40]} args=#{args.inspect[0,40]} body=#{body.inspect[0,60]}" if ENV["INLINE_DEBUG"]
    end

    # Direct substitution: self -> recv, ivar -> raw index on recv, params -> arg exprs. No [:let] rebinding
    # -- [:let] is unreliable as an EXPRESSION VALUE (its register eviction clobbers the result). So operands
    # must be side-effect-free (a bare local/self/literal) and substituted directly; the caller materialises
    # the spliced result (see compile_callm) so it can be used in argument position.
    return nil if !inline_pure?(recv)
    return nil if args.any? { |a| !inline_pure?(a) }
    @inline_count = (@inline_count || 0) + 1
    subst = { :self => recv }
    i = 0
    while i < params.length
      subst[params[i]] = args[i]
      i += 1
    end
    spliced = inline_rewrite(body, subst, recv, offs)   # body is the SINGLE body node (compile_defm's defm[3])
    STDERR.puts "        -> #{spliced.inspect[0,110]}" if ENV["INLINE_DEBUG"]
    spliced
  end
  # Side-effect-free and safely re-substitutable: a bare local var, self, or a small literal.
  def inline_pure?(e)
    e == :self || e == :nil || e == :true || e == :false || e.is_a?(Integer) || e.is_a?(Symbol)
  end

  # An ivar reference symbol (`@x`), excluding class vars (`@@x`).
  def inline_ivar?(s)
    s.is_a?(Symbol) && (t = s.to_s)[0] == ?@ && t[1] != ?@
  end

  # A body is safe to inline only if every statement is a simple expression over {self, ivars, params,
  # literals, indexing, arithmetic, plain method calls}. Anything that would not splice cleanly -- an early
  # return, yield/super/block/lambda, a nested def, loops/case, or a reference to a FREE LOCAL (a bare
  # lowercase symbol that is not a param) -- bails to the direct call. Conservative on purpose; broadened by
  # measurement. The transplant itself is general.
  def safe_to_inline?(body, params)
    body.all? { |s| inline_safe_node?(s, params) }
  end
  def inline_safe_node?(n, params)
    return true if n.nil? || n == :nil || n == :true || n == :false
    return true if n.is_a?(Integer) || n.is_a?(String)
    if n.is_a?(Symbol)
      return true if n == :self || inline_ivar?(n) || params.include?(n)
      return true if ti_const_name?(n)                 # a constant reference
      return false                                     # a bare local / possible_callm on self -> bail
    end
    return false if !n.is_a?(Array)
    h = n[0]
    case h
    when :return, :yield, :super, :block, :proc, :lambda, :defun, :defm, :while, :until,
         :case, :next, :break, :redo, :and_assign, :or_assign, :let, :sexp
      false
    when :assign
      # only an ivar assignment is safe (a local assignment would introduce a call-site local); the RHS and
      # any nested target must also be safe.
      return false if !inline_ivar?(n[1])
      n[2..-1].all? { |c| inline_safe_node?(c, params) }
    else
      # generic node (callm/call/index/arithmetic/if/array/...): every child must be safe.
      n[1..-1].all? { |c| inline_safe_node?(c, params) }
    end
  end
  def ti_const_name?(s)
    t = s.to_s; c = t[0]; c && c >= ?A && c <= ?Z
  end

  # Yield every ivar symbol appearing anywhere in `body`.
  def each_ivar(node, &blk)
    if node.is_a?(Array)
      node.each { |c| each_ivar(c, &blk) }
    elsif inline_ivar?(node)
      blk.call(node)
    end
  end

  # Deep-copy `node`, substituting self/params (via `subst`) and rewriting each ivar `@x` to an explicit
  # indexed load on the receiver: [:index, recv_expr, offset]. An ivar ASSIGNMENT target is rewritten the
  # same way so `@x = v` becomes `recv[offset] = v`.
  def inline_rewrite(node, subst, recv_expr, offs)
    if node.is_a?(Symbol)
      # An ivar read `@x` is self[offset]; make it receiver[offset]. The RAW slot read is the `%s(index ...)`
      # primitive: a bare [:index,...] OUTSIDE a sexp is an untransformed Ruby `recv.[](offset)` method call.
      return [:sexp, [:index, recv_expr, offs[node]]] if inline_ivar?(node)
      return subst[node] if subst.key?(node)
      return node
    end
    return node if !node.is_a?(Array)
    if node[0] == :assign && inline_ivar?(node[1])
      val = node[2] ? inline_rewrite(node[2], subst, recv_expr, offs) : :nil
      return [:sexp, [:assign, [:index, recv_expr, offs[node[1]]], val]]
    end
    node.map { |c| inline_rewrite(c, subst, recv_expr, offs) }
  end

  def find_inline(exps)
    @inline_functions = {}

    exps.depth_first(:defun) do |e|
      if Array(e[3]).first == :__inline
        body = [].concat(e[4..-1])
        @inline_functions[e[1]] = Function.new(e[1], e[2], body, @e.get_local, false)
      end
    end

    #@inline_classes = {}
    #exps.depth_first(:class) do |e|
    #  #STDERR.puts e
    #end
  end

  # Stupid simple inlining, as starting point.
  def rewrite_inline(exps)
    find_inline(exps)

    #STDERR.puts(@inline_functions.inspect)
    exps.depth_first(:call) do |e|
      f = @inline_functions[e[1]]
      if f
        vars = e[2..-1]
        i = 0
        assigns = []
        while (i < f.args.length)
          assigns << [:assign, f.args[i].name, [:sexp].concat(vars[i])]
          i = i + 1
        end
        body = [:let, f.args.map{|a| a.name}].concat(assigns).concat(f.body)
        #preprocess(body)
        e.replace(body)
        :skip
      else
      end
    end
    exps
  end
end
