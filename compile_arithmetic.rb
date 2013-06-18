
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
end
