# frozen_string_literal: true

class Compiler

  def output_body(fscope, func)
    @e.comment("METHOD BODY:")
    if func.body.empty?
      compile_eval_arg(fscope, [:return, 0])
    else
      compile_eval_arg(fscope, func.body)
    end
  end

  def output_arity_check(fscope, name, func)

    minargs = func.minargs
    maxargs = func.maxargs

    if minargs == maxargs && !func.rest?
      # Fixed arity: on mismatch jump to a SHARED per-arity error handler instead of inlining the ~7-line
      # __eqarg call in every method (dead code unless the arity is wrong). The handler reads numargs from
      # -4(%ebp) (the prologue's `pushl %ebx`), which is frame-relative, so one shared block serves every
      # method that expects this arity. See output_arity_fail_handlers. Saves ~7 lines x method.
      n = minargs - 2
      (@arity_fail_handlers ||= {})[n] = true
      @e.cmpl(minargs, :ebx)
      @e.jne("__arity_fail_#{n}")   # fall through to the body on a match
      @e.evict_all
      return
    end

    # Variable arity (min < max, or rest): same sharing, but with too-few (__minarg) and too-many
    # (__maxarg) handlers. On error, jump to the shared handler; otherwise fall through to the body.
    n_min = minargs - 2
    (@minarg_fail_handlers ||= {})[n_min] = true
    @e.cmpl(minargs, :ebx)
    @e.jl("__minarg_fail_#{n_min}")       # too few args
    if !func.rest?
      n_max = maxargs - 2
      (@maxarg_fail_handlers ||= {})[n_max] = true
      @e.cmpl(maxargs, :ebx)
      @e.jg("__maxarg_fail_#{n_max}")     # too many args
    end
    @e.evict_all
  end

  # Emit the shared arity error handlers collected by output_arity_check. Each is the exact code the old
  # inline mismatch path emitted, with the expected count baked in: raise via <helper>(expected, actual),
  # where actual (numargs) is read from -4(%ebp) -- the current method's prologue-saved %ebx. The helper
  # raises and never returns, so no stack cleanup is needed after the call. Reached only on an arity error.
  def output_arity_fail_handlers
    emit_arity_handlers(@arity_fail_handlers, "__arity_fail_", "__eqarg")
    emit_arity_handlers(@minarg_fail_handlers, "__minarg_fail_", "__minarg")
    emit_arity_handlers(@maxarg_fail_handlers, "__maxarg_fail_", "__maxarg")
  end

  def emit_arity_handlers(set, prefix, helper)
    return unless set
    set.keys.sort.each do |n|
      @e.label("#{prefix}#{n}")
      @e.subl(24, :esp)
      @e.movl(n, "(%esp)")            # expected count
      @e.movl("-4(%ebp)", :eax)       # actual numargs (prologue's pushl %ebx)
      @e.movl(:eax, "4(%esp)")
      @e.movl(2, :ebx)               # the helper takes 2 args
      @e.call(helper)
    end
  end

  def output_default_args(fscope, func)
    func.process_defaults do |arg, xindex|
      @e.comment(Emitter::COMMENTS && "Default argument for #{arg.name.to_s} at position #{2 + xindex}")
      @e.comment(Emitter::COMMENTS && arg.default.inspect)
      compile_if(fscope, [:lt, :numargs, 1 + xindex],
        [:assign, ("#"+arg.name.to_s).to_sym, arg.default],
        [:assign, ("#"+arg.name.to_s).to_sym, arg.name]
      )
    end
  end

  def output_function2(xfunc, label, pos)
    fscope = FuncScope.new(xfunc)
    # We extract the usage frequency information and pass it to the emitter
    # to inform the register allocation.
    varfreq = xfunc.body.respond_to?(:extra) ? xfunc.body.extra[:varfreq] : []

    # @FIXME @bug
    # This triggers a bug where if there is a argument
    # with a name colliding with the method name, the env var rewrite
    # appears to rewrite the method name to a closure relative expression.
    #
    @e.func(label, pos, varfreq, xfunc.minargs, xfunc.rest? ? 1000 : xfunc.maxargs, strconst(label)) do
      if xfunc.arity_check
        output_arity_check(fscope, label, xfunc)
      else
        # FIXME: This is strictly only needed for lambdas, as the "self" in scope
        # at the start will be the calling object, not the object that created the lambda.
        @e.evict_regs_for(:self)
      end

      if xfunc.defaultvars > 0
        @e.with_stack(xfunc.defaultvars) do
          output_default_args(fscope, xfunc)
          output_body(fscope,xfunc)
        end
      else
        output_body(fscope,xfunc)
      end
      @e.comment("Reloading self if evicted:")
      # Ensure %esi is intact on exit, if needed:
      reload_self(fscope)
    end
  end

  # Similar to output_constants, but for functions.
  # Compiles all functions, defined so far and outputs the appropriate assembly code.
  def output_functions
    @global_functions.until_empty! do |label, func|
      pos = func.body.respond_to?(:position) ? func.body.position : nil
      fname = pos ? pos.filename : nil
      #@e.include(fname) do
        output_function2(func, label, nil)
      #end
    end
  end

end
