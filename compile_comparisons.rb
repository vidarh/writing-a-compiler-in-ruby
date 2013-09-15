
class Compiler

  # compile_2 was added in compile_arithmetic.rb
  # FIXME: Split these helpers out in separate file
  def compile_comparison(scope, op, left, right)
    compile_2(scope,left,right) do |reg|
      @e.cmpl(@e.result,reg)
      @e.emit("set#{op.to_s}".to_sym, :al)
      @e.movzbl(:al,@e.result)
    end
  end

  def compile_eq(scope,left,right)
    compile_comparison(scope, :e, left,right)
  end

  def compile_ne(scope,left,right)
    compile_comparison(scope, :ne, left,right)
  end

  def compile_lt(scope,left,right)
    compile_comparison(scope, :l, left,right)
  end

  def compile_le(scope,left,right)
    compile_comparison(scope, :le, left,right)
  end

  def compile_gt(scope,left,right)
    compile_comparison(scope, :g, left,right)
  end

  def compile_ge(scope,left,right)
    compile_comparison(scope, :ge, left,right)
  end

end
