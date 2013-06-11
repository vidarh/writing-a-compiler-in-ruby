
# Method to compile arithmetic
class Compiler

  def compile_add(scope, left, right)
    @e.with_register do |reg|
      src = compile_eval_arg(scope,left)
      @e.movl(src,reg)
      @e.save_result(compile_eval_arg(scope,right))
      @e.addl(reg, :eax)
    end
    [:subexpr]
  end

end
