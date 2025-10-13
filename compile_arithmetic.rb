
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
    # Arithmetic right shift
    # S-expr: (sarl shift_amount value_to_shift)
    # left = shift amount, right = value to shift
    # x86 requires shift count in %cl

    # Evaluate first arg (shift amount) and save it
    shift_amt = compile_eval_arg(scope, left)
    @e.pushl(@e.result)

    # Evaluate second arg (value to shift)
    val = compile_eval_arg(scope, right)

    # Pop shift amount into %ecx
    @e.popl(:ecx)

    # Shift value (in %eax) by %cl
    @e.sarl(:cl, @e.result)

    Value.new([:subexpr])
  end

  def compile_sall(scope, left, right)
    # Left shift
    # S-expr: (sall shift_amount value_to_shift)
    # left = shift amount, right = value to shift
    # x86 requires shift count in %cl

    # Evaluate first arg (shift amount) and save it
    shift_amt = compile_eval_arg(scope, left)
    @e.pushl(@e.result)

    # Evaluate second arg (value to shift)
    val = compile_eval_arg(scope, right)

    # Pop shift amount into %ecx
    @e.popl(:ecx)

    # Shift value (in %eax) by %cl
    @e.sall(:cl, @e.result)

    Value.new([:subexpr])
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

  def compile_mulfull(scope, left, right, low_var, high_var)
    # Widening multiply: left * right
    # S-expr: (mulfull a b low_var high_var)
    # Stores low word to low_var, high word to high_var
    # Returns low word in eax

    # Evaluate and save left operand
    compile_eval_arg(scope, left)
    @e.pushl(@e.result)

    # Evaluate right operand
    compile_eval_arg(scope, right)
    @e.movl(@e.result, :ecx)

    # Pop left operand into eax
    @e.popl(:eax)

    # One-operand imull: eax * ecx -> edx:eax
    @e.imull(:ecx)

    # Save both results to stack temporarily
    @e.pushl(:edx)  # high word
    @e.pushl(:eax)  # low word

    # Get low_var location and store
    low_type, low_param = scope.get_arg(low_var)
    @e.popl(:eax)  # Get low word from stack
    @e.save(low_type, :eax, low_param)  # save(type, source, dest)
    @e.pushl(:eax)  # Save back for return

    # Get high_var location and store
    high_type, high_param = scope.get_arg(high_var)
    @e.movl("4(%esp)", :edx)  # Get high word from stack (at esp+4)
    @e.save(high_type, :edx, high_param)  # save(type, source, dest)

    # Clean up and return low word
    @e.popl(:eax)  # Low word as return value
    @e.addl(4, :esp)  # Remove high word from stack

    Value.new([:subexpr])
  end

  def compile_div64(scope, high_word, low_word, divisor, quot_var, rem_var)
    # 64-bit division: (high_word:low_word) / divisor
    # S-expr: (div64 high low divisor quot_var rem_var)
    # Stores quotient to quot_var, remainder to rem_var
    # Returns quotient in eax

    # Evaluate and save all operands
    compile_eval_arg(scope, high_word)
    @e.pushl(@e.result)  # Save high word

    compile_eval_arg(scope, low_word)
    @e.pushl(@e.result)  # Save low word

    compile_eval_arg(scope, divisor)
    @e.movl(@e.result, :ecx)  # Divisor in ecx

    # Set up EDX:EAX for divl (unsigned division)
    @e.popl(:eax)  # Low word (dividend low) -> eax
    @e.popl(:edx)  # High word (dividend high) -> edx

    # Divide EDX:EAX by ECX using unsigned division
    # Result: quotient in EAX, remainder in EDX
    @e.divl(:ecx)

    # Save results to stack
    @e.pushl(:edx)  # remainder
    @e.pushl(:eax)  # quotient

    # Store quotient to quot_var
    quot_type, quot_param = scope.get_arg(quot_var)
    @e.popl(:eax)  # Get quotient from stack
    @e.save(quot_type, :eax, quot_param)
    @e.pushl(:eax)  # Save back for return

    # Store remainder to rem_var
    rem_type, rem_param = scope.get_arg(rem_var)
    @e.movl("4(%esp)", :edx)  # Get remainder from stack
    @e.save(rem_type, :edx, rem_param)

    # Clean up and return quotient
    @e.popl(:eax)  # Quotient as return value
    @e.addl(4, :esp)  # Remove remainder from stack

    Value.new([:subexpr])
  end
end
