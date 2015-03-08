
class Compiler

  # Similar to output_constants, but for functions.
  # Compiles all functions, defined so far and outputs the appropriate assembly code.
  def output_functions
    @global_functions.until_empty! do |name, func|
      # create a function scope for each defined function and compile it appropriately.
      # also pass it the current global scope for further lookup of variables used
      # within the functions body that aren't defined there (global variables and those,
      # that are defined in the outer scope of the function's)

      fscope = FuncScope.new(func)

      pos = func.body.respond_to?(:position) ? func.body.position : nil
      fname = pos ? pos.filename : nil

      @e.include(fname) do
        # We extract the usage frequency information and pass it to the emitter
        # to inform the register allocation.
        varfreq = func.body.respond_to?(:extra) ? func.body.extra[:varfreq] : []
        @e.func(name, pos, varfreq) do
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

          if func.defaultvars > 0
            @e.with_stack(func.defaultvars) do 
              func.process_defaults do |arg, index|
                @e.comment("Default argument for #{arg.name.to_s} at position #{2 + index}")
                @e.comment(arg.default.inspect)
                compile_if(fscope, [:lt, :numargs, 1 + index],
                           [:assign, ("#"+arg.name.to_s).to_sym, arg.default],
                           [:assign, ("#"+arg.name.to_s).to_sym, arg.name])
              end
            end
          end

          @e.comment("METHOD BODY:")

          compile_eval_arg(fscope, func.body)

          @e.comment("Reloading self if evicted:")
          # Ensure %esi is intact on exit, if needed:
          reload_self(fscope)
        end
      end
    end
  end

end
