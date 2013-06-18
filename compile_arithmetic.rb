
# Method to compile arithmetic
class Compiler

  def compile_2(scope, left, right)
    @e.with_register do |reg|
      src = compile_eval_arg(scope,left)
      @e.movl(src,reg)
      @e.save_result(compile_eval_arg(scope,right))
      yield reg
    end
    [:subexpr]    
  end

  def compile_add(scope, left, right)
    compile_2(scope,left,right) do |reg|
      @e.addl(reg, :eax)
    end
  end

  def compile_sub(scope, left, right)
    compile_2(scope,left,right) do |reg|
      @e.subl(:eax,reg)
      @e.save_result(reg)
    end
  end

  def compile_mul(scope, left, right)
    compile_2(scope,left,right) do |reg|
      @e.imull(reg,:eax)
    end
  end


  def compile_div(scope, left, right)
    # FIXME: We really want to be able to request
    # %edx specifically here, as we need it for idivl.
    # Instead we work around that below if we for some
    # reason don't get %edx.
    @e.with_register do |reg|
      src = compile_eval_arg(scope,left)
      @e.movl(:eax,reg)
      @e.save_result(compile_eval_arg(scope,right))
      @e.with_register do |r2|
        if (reg == :edx)
          @e.movl(:eax,r2)
          @e.movl(:edx,:eax)
          divby = r2
        else
          divby = reg
          if (r2 != :edx)
            save = true
            @e.pushl(:edx) 
          end
          @e.movl(reg, :edx)
          @e.movl(:eax,reg)
          @e.movl(:edx,:eax)
        end
        @e.sarl(31, :edx)
        @e.idivl(divby)

        # NOTE: This clobber the remainder made available by idivl,
        # which we'll likely want to be able to save in the future
        @e.popl(:edx) if save
      end
    end
    [:subexpr]    
  end
end
