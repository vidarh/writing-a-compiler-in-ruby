
class Compiler

  def handle_splat(scope,arglist)
    # FIXME: Quick and dirty splat handling:
    # - If the last node has a splat, we cheat and assume it's
    #   from the arguments rather than a proper Ruby Array.
    # - We assume we can just allocate arglist.length+1+numargs
    # - We wastefully do it in two rounds and muck directly
    #   with %esp for now until I figure out how to do this
    #   more cleanly.
    # NOTE: the parameter is `arglist`, NOT `args`: the inner with_register blocks capture it, and naming it
    # `args` collided with the `m.args` method call below -- rewrite_env_vars then rewrote that method name
    # into an __env__ slot (a latent miscompile). Keep it distinct from any method named `args`.
    splat = arglist.last.is_a?(Array) && arglist.last.first == :splat
    numargs = nil

    if !splat
      return yield(arglist,false)
    end

    # FIXME: This is just a disaster waiting to happen
    # (needs proper register allocation)
    @e.comment(Emitter::COMMENTS && "*#{arglist.last.last.to_s}")
    reg = compile_eval_arg(scope,:numargs)

    # "reg" is set to numargs - (number of non-splat arguments to the *method we're in*)
    m = scope.method
    @e.subl(m.args.size-1,reg)
    @e.sall(2,reg)
    @e.subl(reg,@e.sp)
    
    @e.with_register do |argend|
      @e.movl(reg,argend) 
      
      reg = compile_eval_arg(scope,arglist.last.last)
      @e.addl(reg,argend)
      
      @e.with_register do |dest|
        @e.movl(@e.sp,dest)
        lc = @e.get_local
        @e.jmp(lc) # So we can handle the zero argument case

        ls = @e.local
        @e.load_indirect(reg,@e.scratch)
        @e.save_indirect(@e.scratch,dest)
        @e.addl(4,@e.result)
        @e.addl(4,dest)

        @e.local(lc)  # So we can jump straight to condition
        @e.cmpl(reg,argend)
        @e.jne(ls)

        # At this point, dest points to the position *after* the
        # splat arguments. Subtracting the stack pointer, and shifting
        # right twice gives us the number of splat arguments

        @e.subl(@e.sp,dest)
        @e.sarl(2,dest)
        @e.movl(dest,@e.scratch)
        @e.comment(Emitter::COMMENTS && "*#{arglist.last.last.to_s} end")

        arglist.pop
      end
    end

    yield(arglist, true)

    @e.pushl(@e.result)
    reg = compile_eval_arg(scope,:numargs)
    @e.subl(arglist.size+1,reg)
    @e.sall(2,reg)
    @e.movl(reg,@e.scratch)
    @e.popl(@e.result)
    @e.addl(@e.scratch,@e.sp)
  end

end
