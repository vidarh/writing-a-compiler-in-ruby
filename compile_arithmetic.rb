
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

  def compile_mul(scope, left, right)
    compile_2(scope,left,right) do |reg|
      @e.imull(reg,:eax)
    end
  end


  def compile_div(scope, left, right)
    @e.pushl(compile_eval_arg(scope,left))
    
    res = compile_eval_arg(scope,right)
    @e.with_register(:edx) do |dividend|
      @e.with_register do |divisor|
        @e.movl(res,divisor)
        
        # We need the dividend in %eax *and* sign extended into %edx, so 
        # it doesn't matter which one of them we pop it into:
        @e.popl(@e.result) 
        @e.movl(@e.result, dividend)
        @e.sarl(31, dividend)
        @e.idivl(divisor)
      end
    end
    Value.new([:subexpr])
  end
end
