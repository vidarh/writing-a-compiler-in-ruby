
class Compiler
  def compile_jmp_on_false(scope, r, target)
    if r && r.type == :object
      @e.save_result(r)
      @e.evict_all
      @e.cmpl(@e.result_value, "nil")
      @e.je(target)
      @e.cmpl(@e.result_value, "false")
      @e.je(target)
    else
      @e.evict_all
      @e.jmp_on_false(target, r)
    end
  end


  # Changes to make #compile_if comply with real-life requirements
  # makes it hard to use it to implement 'or' without introducing a
  # temporarily variable. First we did that using a global, as a 
  # hack. This does things more "properly" as a first stage to
  # either refactoring out the commonalities with compile_if or 
  # create a "lower level" more generic method to handle conditions
  #
  # (for "or" we really only need a way to explicitly say that
  # the return value of the condition should be left untouched
  # if the "true" / if-then part of the the if condition should remain
  # 
  def compile_or scope, left, right
    @e.comment("compile_or: #{left.inspect} || #{right.inspect}")

    ret = compile_eval_arg(scope,left)
    l_or = @e.get_local + "_or"
    compile_jmp_on_false(scope, ret, l_or)

    l_end_or = @e.get_local + "_end_or"
    @e.jmp(l_end_or)

    @e.comment(".. or:")
    @e.local(l_or)
    or_ret = compile_eval_arg(scope,right)
    @e.local(l_end_or)

    @e.evict_all

    combine_types(ret,or_ret)
  end


  # or_assign is "x ||= y", which translates to x = y if !x
  def compile_or_assign scope, left, right
    @e.comment("compile_or_assign: #{left.inspect} ||= #{right.inspect}")

    ret = compile_eval_arg(scope,left)
    l_or = @e.get_local + "_or"
    compile_jmp_on_false(scope, ret, l_or)

    l_end_or = @e.get_local + "_end_or"
    @e.jmp(l_end_or)

    @e.comment(".. or:")
    @e.local(l_or)
    or_ret = compile_assign(scope, left, right)
    @e.local(l_end_or)

    @e.evict_all

    combine_types(ret,or_ret)
  end


  # Compiles an if expression.
  # Takes the current (outer) scope and two expressions representing
  # the if and else arm.
  # If no else arm is given, it defaults to nil.
  def compile_if(scope, cond, if_arm, else_arm = nil)
    @e.comment("if: #{cond.inspect}")

    res = compile_eval_arg(scope, cond)
    l_else_arm = @e.get_local + "_else"
    compile_jmp_on_false(scope, res, l_else_arm)

    @e.comment("then: #{if_arm.inspect}")
    ifret = compile_eval_arg(scope, if_arm)

    l_end_if_arm = @e.get_local + "_endif"
    @e.evict_all
    @e.jmp(l_end_if_arm) if else_arm
    @e.comment("else: #{else_arm.inspect}")
    @e.local(l_else_arm)
    @e.evict_all
    elseret = compile_eval_arg(scope, else_arm) if else_arm
    @e.evict_all
    @e.local(l_end_if_arm) if else_arm

    # At the moment, we're not keeping track of exactly what might have gone on
    # in the if vs. else arm, so we need to assume all bets are off.
    @e.evict_all

    combine_types(ifret, elseret)
  end

  def compile_return(scope, arg = :nil)
    @e.save_result(compile_eval_arg(scope, arg)) if arg
    @e.movl("-4(%ebp)",:ebx)
    @e.evict_all
    reload_self(scope)
    @e.leave
    @e.ret
    Value.new([:subexpr])
  end

  # Compiles a while loop.
  # Takes the current scope, a condition expression as well as the body of the function.
  def compile_while(scope, cond, body)
    @e.loop do |br|
      var = compile_eval_arg(scope, cond)
      compile_jmp_on_false(scope, var, br)
      compile_exp(ControlScope.new(scope, br), body)
    end
    # FIXME: "while" should return nil.
    return Value.new([:subexpr])
  end

  # "break" has different complexity in different contexts:
  #
  # 1) Lexically inside constructs like "while", break "just" jumps out of the loop
  # This is handled using "controlscope", which intercept requests for a "break label"
  #
  # 2) Inside bare blocks, a break is a potentially non-local jump up the stack to the
  # first instruction *following* the method call that the bare block is attached to.
  #
  # 3) FIXME: ? Verify behaviour for *lambda* as opposed to *proc* and bare blocks.
  #
  # Case #2 is handled by saving the stack frame (which we also need for "preturn")
  # of the location the block is defined. But unlike preturn, where we put this stack
  # frame in place and "leave", thus triggering a return *from* the point we defined
  # the block, for "break" we unwind the stack until "leave" leaves the stack frame
  # in question in %ebp. Then we "ret". This causes us to return to the instruction
  # after the "call" that brought us into the method that took the block as an argument
  # - just where we want to be.
  #
  # See also controlscope.rb
  #
  def compile_break(scope)
    br = scope.break_label
    @e.comment("BREAK")
    if br
      @e.jmp(br)
    else
      # Handling lexical break from block/proc's.
      #
      #    If after leave, %ebp == __stackframe__
      #    then we're where we want to be.
      ret = compile_eval_arg(scope,[:index,:__env__,0])
      @e.movl(ret,:eax)
      l = @e.local
      r = @e.get_local
      @e.leave
      @e.cmpl :eax, :ebp
      @e.jz r
      @e.addl(4,:esp)
      @e.jmp l
      @e.local(r)
      @e.ret
    end
    @e.evict_all
    return Value.new([:subexpr])
  end
end
