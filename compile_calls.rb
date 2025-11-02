#
# Method related to function and method calls,
# including yield and super.
#
#

class Compiler

  def compile_args_nosplat(scope, ob, args, dynamic_adj = false, &block)
    # FIXME: This used to use "with_stack" which aligns to 16 byte boundaries,
    # but lifted this in here due to dynamically adjusting the stack based on
    # %ebx. Need to determine exactly what to do about this size - it needs to
    # be bigger than args.length for some reason, but unsure exactly why and
    # how much.
    adj = Emitter::PTR_SIZE * (args.length+4)
    @e.subl(adj, :esp)
    args.each_with_index do |a, i|
      param = compile_eval_arg(scope, a)
      @e.save_to_stack(param, i)
    end
    @e.movl(args.length, :ebx)

    yield

    if dynamic_adj
      # Always dynamically adjust the stack based on %ebx for method calls
      # (as opposed to C-library calls) due to potential of hitting a
      # method_missing thunk or anything else that might mess around with the
      # argument list before returning from the call.
      @e.comment("Static adj: #{adj}")
      @e.addl(4, :ebx) # Need to correspond to the extra space used when assigning "adj" above.
      @e.sall(2, :ebx) 
      @e.addl(:ebx, :esp)
    else
      @e.addl(adj, :esp)
    end
  end

  def copy_splat_loop(splatcnt, indir)
    @e.loop do |br,_|
      @e.testl(splatcnt, splatcnt)
      @e.je(br)
      # x86 will be the death of me.
      @e.pushl("(%eax)")
      @e.popl("(%#{indir.to_s})")
      @e.addl(4,:eax)
      @e.addl(4,indir)
      @e.subl(1,splatcnt)
    end
  end

  # For a splat argument, push it onto the stack,
  # forwards relative to register "indir".
  #
  # FIXME: This method is almost certainly much
  # less efficient than it could be.
  #
  def compile_args_copysplat(scope, a, indir)
    @e.with_register do |splatcnt|
      if a[1] == :__copysplat
        @e.comment("SPLAT COPY")
        param = @e.save_to_reg(compile_eval_arg(scope, [:sub, :numargs, 2]))
        @e.movl(param, splatcnt)
        param = compile_eval_arg(scope, a[1])
        copy_splat_loop(splatcnt, indir)
      else
        @e.comment("SPLAT ARRAY")
        param = compile_eval_arg(scope, a[1])
        @e.addl(4,param)
        @e.load_indirect(param, splatcnt)
        @e.addl(4,param)
        @e.load_indirect(param, :eax)
        @e.testl(:eax,:eax)
        l = @e.get_local

        # If Array class ptr has not been allocated yet:
        @e.je(l)
        copy_splat_loop(splatcnt, indir)
        @e.local(l)
      end
    end

  end

  def compile_args_splat_loop(scope, args, indir)
    args.each do |a|
      ary = a.is_a?(Array)
      sp = false
      if ary
        if a[0] == :splat
          sp = true
        end
      end
      # ary && (a[0] == :splat)
      if sp
        compile_args_copysplat(scope, a, indir)
      else
        param = compile_eval_arg(scope, a)
        @e.save_indirect(param, indir)
        @e.addl(4, indir)
      end
    end
  end

  def compile_args_splat(scope, ob, args)
    # Because Ruby evaluation order is left to right,
    # we need to first figure out how much space we need on
    # the stack.
    #
    # We do that by first building up an expression that
    # adds up the static elements of the parameter list
    # and the result of retrieving 'Array#length' from
    # each splatted array.
    #
    # (FIXME: Note that we're not actually type-checking
    # what is *actually* passed)
    #
    num_fixed = 0
    exprlist = []
    args.each_with_index do |a, i|
      if a.is_a?(Array) && a[0] == :splat
        if a[1] == :__copysplat
          exprlist << [:sub, :numargs, 2]
        else
          # We do this, rather than Array#length, because the class may not
          # have been created yet. This *requires* Array's @len ivar to be
          # in the first ivar;
          # FIXME: should enforce this.
          exprlist << [:index, a[1], 1]
        end
      else
        num_fixed += 1
      end
    end
    expr = num_fixed
    while e = exprlist.pop
      expr = [:add, e, expr]
    end

    @e.comment("BEGIN Calculating argument count for splat")
    ret = compile_eval_arg(scope, expr)
    @e.movl(@e.result, @e.scratch)
    @e.comment("END Calculating argument count for splat; numargs is now in #{@e.scratch.to_s}")

    @e.comment("Moving stack pointer to start of argument array:")
    @e.imull(4,@e.result)

    # esp now points to the start of the arguments; ebx holds numargs,
    # and end_of_arguments(%esp) also holds numargs
    @e.subl(@e.result, :esp)

    @e.comment("BEGIN Pushing arguments:")
    @e.with_register do |indir|
      # We'll use indir to put arguments onto the stack without clobbering esp:
      @e.movl(:esp, indir)
      @e.pushl(@e.scratch)
      @e.comment("BEGIN args.each do |a|")
      compile_args_splat_loop(scope, args, indir)
      @e.comment("END args.each")
      @e.popl(@e.scratch)
    end
    @e.comment("END Pushing arguments")
    yield
    @e.comment("Re-adjusting stack post-call:")
    @e.imull(4,@e.scratch)
    @e.addl(@e.scratch, :esp)
  end

  def compile_args(scope, ob, args, dynamic_adjust=false, &block)
    @e.caller_save do
      splat = args.detect {|a| a.is_a?(Array) && a.first == :splat }

      #FIXME Mentioned here to lift vars
      scope
      block
      dynamic_adjust

      if !splat
        compile_args_nosplat(scope,ob,args,dynamic_adjust, &block)
      else
        compile_args_splat(scope,ob,args, &block)
      end
    end
  end

  def compile_callm_args(scope, ob, args, &block)
    compile_args(scope, ob, [ob].concat(args), true, &block)
  end



  # Compiles a function call.
  # Takes the current scope, the function to call as well as the arguments
  # to call the function with.
  def compile_call(scope, func, args, block = nil)
    return compile_yield(scope, args, block) if func == :yield

    # Handle 'include ModuleName' as compile-time module inclusion
    if func == :include
      # args is array of module names, but we only support single module for now
      mod_name = args.is_a?(Array) ? args[0] : args
      return compile_include(scope, mod_name)
    end

    # This is a bit of a hack. get_arg will also be called from
    # compile_eval_arg below, but we need to know if it's a callm
    fargs = get_arg(scope, func)

    return compile_super(scope, args,block) if func == :super
    return compile_callm(scope,:self, func, args,block) if fargs and fargs[0] == :possible_callm || fargs[0] == :global

    args = [args] if !args.is_a?(Array)
    compile_args(scope, func, args) do
      scope
      func

      r = get_arg(scope,func)
      if r[0] == :addr
        @e.call(r[1].to_s)
      else
        @e.call(compile_eval_arg(scope, func))
      end
    end

    @e.evict_regs_for(:self)
    reload_self(scope)
    return Value.new([:subexpr])
  end


  # Load class for the object whose pointer is in %esi.
  #
  # For now, this is done by testing bit 0, and if it
  # is set we know this isn't a valid pointer to a Class
  # object. Instead we assume it is a Fixnum.
  #
  # This is similar to MRI, but MRI uses type tags for
  # more types of objects. We probably will here too
  # in the future (e.g. Float when it's added, at least)
  #
  # Upside: Far less need for garbage collection.
  # Downside: The cost of *this* every time we need the
  # class pointer. This can be mitigated somewhat by
  # better code generation (e.g. keeping class pointers
  # for objects that are accessed multiple times;
  # figuring out inlining and the like, but requires more
  # effort to optimize. As a first stage, however, this
  # will do as it makes self-compilation viable for this
  # compiler for the first time.
  #
  def load_class(scope)
    @e.testl(1, :esi)
    l1 = @e.get_local
    l2 = @e.get_local
    @e.jz(l1)
    @e.load(:global, :Fixnum)
    @e.jmp(l2)
    @e.label(l1)
    @e.load_indirect(:esi, :eax)
    @e.label(l2)
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

  # FIXME: @bug May need to do this as a rewrite, as if block is taken in, and
  # then another block is passed to another method, that other method can not
  # contain "yield", as it needs to go through a let_env rewrite.
  #
  # Yield to the supplied block
  def compile_yield(scope, args, block)
    @e.comment("yield")
    args ||= []
    compile_callm(scope, :__closure__, :call, args, block)
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
    return compile_super(scope, args,block) if method == :super and ob == :self

    @e.comment("callm #{ob.inspect}.#{method.inspect}")
    trace(nil,"=> callm #{ob.inspect}.#{method.inspect}\n")

    stackfence do
      args ||= []
      args = [args] if !args.is_a?(Array) # FIXME: It's probably better to make the parser consistently pass an array


      if args.last.kind_of?(Array) && args.last[0] == :to_block
        block = args.last[1]
        args.pop
      end

      args = [block ? block : 0] + args

      off = nil
      if method.is_a?(Symbol)
        off = @vtableoffsets.get_offset(method)
        if !off
          # Argh. Ok, then. Lets do send
          off = @vtableoffsets.get_offset(:__send__)
          args.insert(1,":#{method}".to_sym)
          # warning("WARNING: No vtable offset for '#{method}' (with args: #{args.inspect}) -- you're likely to get a method_missing")
          #error(err_msg, scope, [:callm, ob, method, args])
          m = off
        else
          m = "__voff__#{clean_method_name(method)}"
        end
      else
        # In this case, the method is provided as an expression
        # generating the *address*, which is evaluated beow.
      end

      compile_callm_args(scope, ob, args) do
        if ob != :self
          @e.load_indirect(@e.sp, :esi) 
        else
          @e.comment("Reload self?")
          reload_self(scope)
        end

        load_class(scope) # Load self.class into %eax
        load_super(scope) if do_load_super

        if off
          @e.callm(m)
        else
          # NOTE: The expression in "method" can not
          # include a function call, as it'll clobber
          # %ebx
          @e.call(compile_eval_arg(scope,method))
        end

        # FIXME: Unsure if the below check is
        # inherently unsafe, or currently unsafe
        # due to abug elsewhere, but removing it
        # solves some register invalidation problems,
        # so commenting out for now.
#        if ob != :self
          @e.comment("Evicting self")
          @e.evict_regs_for(:self)
#        end
      end
    end

    @e.comment("callm #{ob.to_s}.#{method.to_s} END")
    trace(nil,"<= callm #{ob.to_s}.#{method.to_s}\n")

    return Value.new([:subexpr], :object)
  end

end
