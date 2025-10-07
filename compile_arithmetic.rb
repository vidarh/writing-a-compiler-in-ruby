
# Method to compile arithmetic
class Compiler

  def compile_2(scope, left, right)
    src = compile_eval_arg(scope,left)
    @e.with_register_for(src) do |reg|
#      @e.emit(:movl, src, reg)
      @e.save_result(compile_eval_arg(scope,right))
      yield reg
    end
    Value.new([:subexpr], nil)
  end

  def compile_shl(scope, left)
    src = compile_eval_arg(scope, left)
    @e.shl(src)
    @e.save_result(src)
    Value.new([:subexpr])
  end

  def compile_sar(scope, left)
    src = compile_eval_arg(scope, left)
    @e.sar(src)
    @e.save_result(src)
    Value.new([:subexpr])
  end

  def compile_sarl(scope, left, right)
    # FIXME: Dummy
    compile_sar(scope,left)
  end

  def compile_sall(scope, left, right)
    # FIXME: Dummy
    compile_shl(scope,left)
  end

  def compile_add(scope, left, right)
    compile_2(scope,left,right) do |reg|
      @e.addl(reg, @e.result)
    end
  end

  def compile_sub(scope, left, right)
    compile_2(scope,left,right) do |reg|
      @e.subl(:eax,reg)
      @e.save_result(reg)
    end
  end

  def compile_bitand(scope, left, right)
    compile_2(scope,left,right) do |reg|
      @e.andl(reg, @e.result)
    end
  end

  def compile_bitor(scope, left, right)
    compile_2(scope,left,right) do |reg|
      @e.orl(reg, @e.result)
    end
  end

  def compile_bitxor(scope, left, right)
    compile_2(scope,left,right) do |reg|
      @e.xorl(reg, @e.result)
    end
  end

  def compile_mul(scope, left, right)
    compile_2(scope,left,right) do |reg|
      @e.imull(reg,:eax)
    end
  end


  def compile_div(scope, left, right, &block)
    @e.pushl(compile_eval_arg(scope,left))
    
    res = compile_eval_arg(scope,right)
    # FIXME @bug
    # block_given? does not work in nested
    # lambdas
    bg = block_given?
    @e.with_register(:edx) do |dividend|
      xdividend = dividend
      @e.with_register do |divisor|
        # FIXME: @bug
        # dividend gets set incorrectly due to a compiler
        # bug in handling of nested lambdas, so using xdividend above instead.

        @e.movl(res,divisor)
        # We need the dividend in %eax *and* sign extended into %edx, so 
        # it doesn't matter which one of them we pop it into:
        @e.popl(@e.result)
        @e.movl(@e.result, xdividend)
        @e.sarl(31, xdividend)
        @e.idivl(divisor)

        if bg
          block.call
        end
      end
    end
    Value.new([:subexpr])
  end

  def compile_mod(scope, left, right)
    compile_div(scope,left,right) do
      @e.movl(:edx, @e.result)
    end
  end
end
