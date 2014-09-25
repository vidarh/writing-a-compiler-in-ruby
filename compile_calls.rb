#
# Method related to function and method calls,
# including yield and super.
#
#

class Compiler

  # Push arguments onto the stack
  def push_args(scope,args, offset = 0)
    args.each_with_index do |a, i|
      param = compile_eval_arg(scope, a)
      @e.save_to_stack(param, i + offset)
    end
  end


  # Compiles a function call.
  # Takes the current scope, the function to call as well as the arguments
  # to call the function with.
  def compile_call(scope, func, args, block = nil)
    return compile_yield(scope, args, block) if func == :yield

    # This is a bit of a hack. get_arg will also be called from
    # compile_eval_arg below, but we need to know if it's a callm
    fargs = get_arg(scope, func)

    return compile_super(scope, args,block) if func == :super
    return compile_callm(scope,:self, func, args,block) if fargs && fargs[0] == :possible_callm

    args = [args] if !args.is_a?(Array)
    @e.caller_save do
      handle_splat(scope, args) do |args,splat|
        @e.comment("ARGS: #{args.inspect}; #{splat}")
        @e.with_stack(args.length, !splat) do
          @e.pushl(@e.scratch)
          push_args(scope, args,1)
          @e.popl(@e.scratch)
          @e.call(compile_eval_arg(scope, func))
        end
      end
    end

    @e.evict_regs_for(:self)
    reload_self(scope)
    return Value.new([:subexpr])
  end


  # If adding type-tagging, this is the place to do it.
  # In the case of type tagging, the value in %esi
  # would be matched against the suitable type tags
  # to determine the class, instead of loading the class
  # from the first long of the object.
  def load_class(scope)
    @e.load_indirect(:esi, :eax)
  end

  # Load the super-class pointer
  def load_super(scope)
    @e.load_instance_var(:eax, 3)
  end
                

  # if we called a method on something other than self,
  # or a function, we have or may have clobbered %esi,
  # so lets reload it.
  def reload_self(scope)
    t,a = get_arg(scope,:self)
  end

  # Yield to the supplied block
  def compile_yield(scope, args, block)
    @e.comment("yield")
    args ||= []
    compile_callm(scope, :__closure__, :call, args, block)
  end

  def compile_callm_args(scope, ob, args)
    handle_splat(scope,args) do |args, splat|
      @e.with_stack(args.length+1, !splat) do
        # we're for now going to assume that %ebx is likely
        # to get clobbered later in the case of a splat,
        # so we store it here until it's time to call the method.
        @e.pushl(@e.scratch)
        
        ret = compile_eval_arg(scope, ob)
        @e.save_to_stack(ret, 1)
        args.each_with_index do |a,i|
          param = compile_eval_arg(scope, a)
          @e.save_to_stack(param, i+2)
        end
        
        # Pull the number of arguments off the stack
        @e.popl(@e.scratch)
        yield  # And give control back to the code that actually does the call.
      end
    end
  end


  # Compiles a super method call
  #
  def compile_super(scope, args, block = nil)
    method = scope.method.name
    @e.comment("super #{method.inspect}")
    trace(nil,"=> super #{method.inspect}\n")
    ret = compile_callm(scope, :self, method, args, block, true)
    trace(nil,"<= super #{method.inspect}\n")
    ret
  end

  # Compiles a method call to an object.
  # Similar to compile_call but with an additional object parameter
  # representing the object to call the method on.
  # The object gets passed to the method, which is just another function,
  # as the first parameter.
  def compile_callm(scope, ob, method, args, block = nil, do_load_super = false)
    # FIXME: Shouldn't trigger - probably due to the callm rewrites
    return compile_yield(scope, args, block) if method == :yield and ob == :self

    @e.comment("callm #{ob.inspect}.#{method.inspect}")
    trace(nil,"=> callm #{ob.inspect}.#{method.inspect}\n")

    stackfence do
      args ||= []
      args = [args] if !args.is_a?(Array) # FIXME: It's probably better to make the parser consistently pass an array
      args = [block ? block : 0] + args

      off = @vtableoffsets.get_offset(method)
      if !off
        # Argh. Ok, then. Lets do send
        off = @vtableoffsets.get_offset(:__send__)
        args.insert(1,":#{method}".to_sym)
        warning("WARNING: No vtable offset for '#{method}' (with args: #{args.inspect}) -- you're likely to get a method_missing")
        #error(err_msg, scope, [:callm, ob, method, args])
        m = off
      else
        m = "__voff__#{clean_method_name(method)}"
      end

      @e.caller_save do
        compile_callm_args(scope, ob, args) do
          if ob != :self
            @e.load_indirect(@e.sp, :esi) 
          else
            @e.comment("Reload self?")
            reload_self(scope)
          end

          load_class(scope) # Load self.class into %eax
          load_super(scope) if do_load_super
          
          @e.callm(m)
          if ob != :self
            @e.comment("Evicting self") 
            @e.evict_regs_for(:self) 
          end
        end
      end
    end

    @e.comment("callm #{ob.to_s}.#{method.to_s} END")
    trace(nil,"<= callm #{ob.to_s}.#{method.to_s}\n")

    return Value.new([:subexpr], :object)
  end

end
