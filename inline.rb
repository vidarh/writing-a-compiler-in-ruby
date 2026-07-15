
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
  # Receiver and arguments must be side-effect-free (see inline_side_effect_free?) so they can be
  # substituted directly into the body without temp binding. Multiple uses therefore do not re-run side
  # effects. Returns a spliceable AST, or nil to fall back to the direct devirt call.
  def inline_devirt_body(scope, recv, args, dclass, defm)
    # Only inline inside a method/block body. At top level (main's @global_scope) a bare local used as the
    # raw-index base resolves through a path the `%s(index ...)` primitive can't load (atype "e"); those call
    # sites are rare and fall back to the direct devirt call. Method params/locals/self work fine.
    return inline_bail(dclass, defm, :not_in_funcscope) if !scope_has_funcscope?(scope)
    if ENV["INLINE_DEBUG"]
      @inl_calls = (@inl_calls || 0) + 1
      STDERR.puts "[inl entry ##{@inl_calls}] #{dclass}##{defm[1]}" if @inl_calls % 200 == 1 || @inl_calls < 5
    end
    params = defm[2]
    return inline_bail(dclass, defm, :bad_params, params.inspect[0,40]) if !params.is_a?(Array)
    # Allow required and optional positional params. Optional params are filled with their
    # side-effect-free default expressions when the call provides fewer arguments. Rest/block
    # params and impure defaults are rejected.
    param_entries = []
    required_count = 0
    params.each do |p|
      if p.is_a?(Symbol)
        param_entries << [:required, p]
        required_count += 1
      elsif p.is_a?(Array) && p[0].is_a?(Symbol) && p[1] == :default && p.length == 3
        default_expr = p[2]
        return inline_bail(dclass, defm, :impure_default, p.inspect[0,40]) if !inline_side_effect_free?(default_expr)
        param_entries << [:optional, p[0], default_expr]
      else
        return inline_bail(dclass, defm, :unsupported_param, p.inspect[0,40])
      end
    end
    param_names = param_entries.map { |e| e[1] }
    total_params = param_names.length
    args = [] if args.nil?
    args = [args] if !args.is_a?(Array)
    if args.length < required_count || args.length > total_params
      return inline_bail(dclass, defm, :arg_count_mismatch, "args=#{args.length} required=#{required_count} total=#{total_params}")
    end
    # Fill missing trailing arguments with deep-copied default expressions. Work on a copy so we
    # do not mutate the caller's args array if we later bail out and it falls back to a direct call.
    effective_args = args.dup
    while effective_args.length < total_params
      entry = param_entries[effective_args.length]
      effective_args << __deep_dup_node(entry[2])
    end
    args = effective_args
    body = defm[3]                                    # compile_defm compiles this SINGLE node as the body
    return inline_bail(dclass, defm, :no_body) if body.nil?

    # Strip a trailing explicit return where it is equivalent to the body's value.
    body, _ = inline_unwrap_return(body)
    return inline_bail(dclass, defm, :return_unwrap_failed) if body.nil?
    return inline_bail(dclass, defm, :unsafe_body, body.inspect[0,60]) if !inline_safe_node?(body, param_names)

    cscope = @classes[dclass] || @classes["Object__#{dclass}".to_sym]
    return inline_bail(dclass, defm, :no_class_scope) if !cscope
    # Pre-resolve every ivar offset up front; bail the whole inline if any is unknown.
    offs = {}
    ok = true
    each_ivar(body) do |iv|
      o = cscope.find_ivar_offset(iv)
      if o then offs[iv] = o else ok = false end
    end
    return inline_bail(dclass, defm, :unknown_ivar) if !ok

    if ENV["INLINE_MAX"]
      @inline_dbg = (@inline_dbg || 0) + 1
      return nil if @inline_dbg > ENV["INLINE_MAX"].to_i
      STDERR.puts "[inline ##{@inline_dbg}] #{dclass}##{defm[1]} recv=#{recv.inspect[0,40]} args=#{args.inspect[0,40]} body=#{body.inspect[0,60]}" if ENV["INLINE_DEBUG"]
    end

    # Direct substitution: self -> recv, ivar -> raw index on recv, params -> arg exprs. Operands must be
    # side-effect-free so they can be duplicated/substituted directly; the caller materialises the spliced
    # result (see compile_callm) so it can be used in argument position.
    return inline_bail(dclass, defm, :impure_recv, recv.inspect[0,40]) if !inline_side_effect_free?(recv)
    args.each_with_index do |a, i|
      return inline_bail(dclass, defm, :impure_arg, "arg#{i}=#{a.inspect[0,40]}") if !inline_side_effect_free?(a)
    end
    @inline_count = (@inline_count || 0) + 1
    subst = { :self => recv }
    i = 0
    while i < param_names.length
      subst[param_names[i]] = args[i]
      i += 1
    end
    spliced = inline_rewrite(body, subst, recv, offs)   # body is the SINGLE body node (compile_defm's defm[3])
    STDERR.puts "        -> #{spliced.inspect[0,110]}" if ENV["INLINE_DEBUG"]
    spliced
  end

  # Diagnostic helper for INLINE_DEBUG=2: log why a candidate was rejected. Throttled per (method,reason)
  # so the output is readable; returns nil so it can be used as `return inline_bail(...)`.
  def inline_bail(dclass, defm, reason, detail = nil)
    if ENV["INLINE_DEBUG"] == "2"
      @inline_bails ||= Hash.new(0)
      key = "#{dclass}##{defm[1]}:#{reason}"
      @inline_bails[key] += 1
      if @inline_bails[key] <= 3
        msg = "[inline bail] #{dclass}##{defm[1]}: #{reason}"
        msg += " #{detail}" if detail
        STDERR.puts msg
      end
    end
    nil
  end

  # Side-effect-free and safely re-substitutable: a bare local var, self, or a small literal.
  def inline_pure?(e)
    e == :self || e == :nil || e == :true || e == :false || e.is_a?(Integer) || e.is_a?(Symbol)
  end

  # True for expressions that can be duplicated or used multiple times without changing program semantics:
  # literals, self/params/locals, ivar reads, constants, and pure arithmetic/raw-index operations. Excludes
  # anything that allocates, calls a method, performs assignment, or contains control flow.
  def inline_side_effect_free?(e)
    return true if e == :self || e == :nil || e == :true || e == :false
    return true if e.is_a?(Integer) || e.is_a?(String)
    if e.is_a?(Symbol)
      return true if inline_ivar?(e) || ti_const_name?(e)
      return true                                   # a local/param/constant/keyword symbol
    end
    return false if !e.is_a?(Array)
    return true if inline_safe_sexp?(e)
    h = e[0]
    case h
    when :call, :callm, :safe_callm, :yield, :super, :block, :proc, :lambda, :defun, :defm,
         :while, :until, :case, :return, :next, :break, :redo,
         :assign, :and_assign, :or_assign, :let, :sexp, :array, :hash, :float
      false
    else
      e[1..-1].all? { |c| inline_side_effect_free?(c) }
    end
  end

  # Known-safe %s() forms that can appear in a side-effect-free operand or inlinable body.
  # The compiler lowers Ruby literals to :sexp wrappers, so rejecting :sexp outright blocks
  # almost all literal receivers/arguments and many simple core-library getters.
  # `params` is non-nil when we are checking a method body (so parameters/self/ivars are in scope);
  # nil when checking a receiver/argument for side-effect freedom.
  def inline_safe_sexp?(sexp, params = nil)
    return false if !sexp.is_a?(Array) || sexp[0] != :sexp || sexp.length != 2
    inner = sexp[1]
    # %s(sexp N) - tagged integer literal produced by rewrite_integer_constant.
    return true if inner.is_a?(Integer)
    # %s(sexp :__S_name) - symbol literal produced by rewrite_symbol_constant.
    return true if inner.is_a?(Symbol) && inner.to_s.start_with?("__S_")
    return false if !inner.is_a?(Array)
    h = inner[0]
    case h
    when :__int
      # %s(__int expr) - raw integer tagging, pure if the operand is.
      inner.length == 2 && inline_safe_sexp_operand?(inner[1], params)
    when :index
      # %s(index obj offset) - raw slot read, pure if obj/offset are.
      inner.length == 3 &&
        inline_safe_sexp_operand?(inner[1], params) &&
        inline_safe_sexp_operand?(inner[2], params)
    when :call
      # Pure literal constructors emitted by the compiler.
      return false if inner.length != 3
      fname = inner[1]
      (fname == :__get_string || fname == :__get_symbol) && inner[2].is_a?(Symbol)
    else
      false
    end
  end

  # An operand inside a known-safe %s() expression. We allow self/ivar/param/const/literal
  # and simple recursively-safe primitive operations, but not calls/assignments/control flow.
  def inline_safe_sexp_operand?(e, params)
    return true if e == :self || e.is_a?(Integer)
    if e.is_a?(Symbol)
      return true if inline_ivar?(e)
      return true if params && params.include?(e)
      return true if ti_const_name?(e)
      return true if e.to_s.start_with?("__S_")
      return false
    end
    return false if !e.is_a?(Array)
    # Nested primitive operator arrays (e.g. %s(index self (+ offset 1))).
    # The head is treated as an operator; we only verify its operands.
    e[1..-1].all? { |c| inline_safe_sexp_operand?(c, params) }
  end

  # If `body` is a single [:return, expr], return [expr, true]. If it is a [:do, ..., [:return, expr]]
  # whose final statement is a return and there is no earlier return, return [the :do with the trailing
  # return stripped, true]. Otherwise return [body, false].
  def inline_unwrap_return(body)
    return [body, false] if !body.is_a?(Array)
    if body[0] == :return
      return [body[1], true]
    end
    if body[0] == :do && body.length > 1
      last = body[-1]
      if last.is_a?(Array) && last[0] == :return
        new_body = body.dup
        new_body[-1] = last[1]          # replace trailing return with its expression (may be nil)
        return [new_body, true]
      end
    end
    [body, false]
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
         :case, :next, :break, :redo, :and_assign, :or_assign, :let
      false
    when :sexp
      inline_safe_sexp?(n, params)
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
