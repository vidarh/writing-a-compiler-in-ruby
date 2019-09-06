
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
    compile_if(fscope, [:lt, :numargs, minargs],
                        [:sexp,[:call, :printf,
                                ["ArgumentError: In %s - expected a minimum of %d arguments, got %d\n",
                                name, minargs - 2, [:sub, :numargs,2]]], [:div,1,0] ])
    if !func.rest?
      maxargs = func.maxargs
      compile_if(fscope, [:gt, :numargs, maxargs],
                        [:sexp,[:call, :printf,
                               ["ArgumentError: In %s - expected a maximum of %d arguments, got %d\n",
                                name, maxargs - 2, [:sub, :numargs,2]]],  [:div,1,0] ])
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
      output_arity_check(fscope, label, xfunc)

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
