
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

    # Variable arity (min < max, or rest): keep the inline min/max checks.
    l = @e.get_local
    @e.cmpl(minargs, :ebx)
    @e.jge(l)
    compile_eval_arg(fscope,
      [:sexp,[:call, :__minarg, [minargs - 2, :numargs]]])
    if !func.rest?
      @e.cmpl(maxargs, :ebx)
      @e.jle(l)
      compile_eval_arg(fscope,
                      [:sexp,[:call, :__maxarg, [maxargs - 2, :numargs]]])
    end
    @e.label(l)
    @e.evict_all
  end

  # Emit the shared fixed-arity error handlers collected by output_arity_check. Each is the exact code the
  # old inline mismatch path emitted, with the expected count baked in: raise via __eqarg(expected, actual),
  # where actual (numargs) is read from -4(%ebp) -- the current method's prologue-saved %ebx. __eqarg raises
  # and never returns, so no stack cleanup is needed after the call. Reached only on an arity mismatch.
  def output_arity_fail_handlers
    return unless @arity_fail_handlers
    @arity_fail_handlers.keys.sort.each do |n|
      @e.label("__arity_fail_#{n}")
      @e.subl(24, :esp)
      @e.movl(n, "(%esp)")            # expected = minargs - 2
      @e.movl("-4(%ebp)", :eax)       # actual numargs (prologue's pushl %ebx)
      @e.movl(:eax, "4(%esp)")
      @e.movl(2, :ebx)                # __eqarg takes 2 args
      @e.call("__eqarg")
    end
  end

  def output_default_args(fscope, func)
    func.process_defaults do |arg, xindex|
      @e.comment("Default argument for #{arg.name.to_s} at position #{2 + xindex}")
      @e.comment(arg.default.inspect)
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
