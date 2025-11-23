
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

  def compile_jmp_on_true(scope, r, target)
    # Jump on true is the inverse of jump on false
    # We jump if the value is NOT nil and NOT false
    if r && r.type == :object
      @e.save_result(r)
      @e.evict_all
      # Create a skip label - we'll jump over the target jump if value is false/nil
      skip = @e.get_local
      @e.cmpl(@e.result_value, "nil")
      @e.je(skip)
      @e.cmpl(@e.result_value, "false")
      @e.je(skip)
      # Value is truthy - jump to target
      @e.jmp(target)
      @e.local(skip)
    else
      @e.evict_all
      # For non-object types, implement manually
      skip = @e.get_local
      @e.jmp_on_false(skip, r)
      @e.jmp(target)
      @e.local(skip)
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
    @e.save_result(ifret)  # Save then-branch result to %eax

    l_end_if_arm = @e.get_local + "_endif"
    @e.evict_all
    @e.jmp(l_end_if_arm) if else_arm
    @e.comment("else: #{else_arm.inspect}")
    @e.local(l_else_arm)
    @e.evict_all
    # FIXME: Workaround for missing initialisation of local vars
    elseret = nil
    if else_arm
      elseret = compile_eval_arg(scope, else_arm)
      @e.save_result(elseret)  # Save else-branch result to %eax
    end
    @e.evict_all
    @e.local(l_end_if_arm) if else_arm

    # At the moment, we're not keeping track of exactly what might have gone on
    # in the if vs. else arm, so we need to assume all bets are off.
    @e.evict_all

    combine_types(ifret, elseret)
  end

  # Compiles an unless expression by swapping the then/else arms
  def compile_unless(scope, cond, unless_arm, else_arm = nil)
    # unless cond; A; else; B; end  =>  if cond; B; else; A; end
    compile_if(scope, cond, else_arm, unless_arm)
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
    # We need two exit labels:
    # - normal_exit: for when condition becomes false (returns nil)
    # - break_label: for when break is executed (returns break value)
    @e.evict_all
    break_label = @e.get_local
    normal_exit = @e.get_local
    loop_label = @e.local

    var = compile_eval_arg(scope, cond)
    compile_jmp_on_false(scope, var, normal_exit)
    # Handle bare symbols/values in body - evaluate them directly
    if body.is_a?(Array)
      compile_exp(ControlScope.new(scope, break_label, loop_label), body)
    else
      compile_eval_arg(ControlScope.new(scope, break_label, loop_label), body)
    end
    @e.evict_all
    @e.jmp(loop_label)

    # Normal exit: set %eax to nil
    @e.local(normal_exit)
    nilval = compile_eval_arg(scope, :nil)
    @e.movl(nilval, :eax) if nilval != :eax

    # Break label: %eax already has the break value
    @e.local(break_label)

    return Value.new([:subexpr])
  end

  # Compiles an until loop (inverse of while).
  # Takes the current scope, a condition expression as well as the body of the function.
  def compile_until(scope, cond, body)
    # Same structure as compile_while but with jmp_on_true instead of jmp_on_false
    @e.evict_all
    break_label = @e.get_local
    normal_exit = @e.get_local
    loop_label = @e.local

    var = compile_eval_arg(scope, cond)
    compile_jmp_on_true(scope, var, normal_exit)  # Jump on true (opposite of while)
    # Handle bare symbols/values in body - evaluate them directly
    if body.is_a?(Array)
      compile_exp(ControlScope.new(scope, break_label, loop_label), body)
    else
      compile_eval_arg(ControlScope.new(scope, break_label, loop_label), body)
    end
    @e.evict_all
    @e.jmp(loop_label)

    # Normal exit: set %eax to nil
    @e.local(normal_exit)
    nilval = compile_eval_arg(scope, :nil)
    @e.movl(nilval, :eax) if nilval != :eax

    # Break label: %eax already has the break value
    @e.local(break_label)

    return Value.new([:subexpr])
  end

  # "next" acts differently in a control structure vs. block
  #
  # In "while" etc, "next" jumps to the next iteration.
  # In a block, "next" exits the block.
  #
  def compile_next(scope, arg = :nil)
    l = scope.loop_label
    if l
      @e.jmp(l)
      @e.evict_all
      return Value.new([:subexpr])
    end
    compile_return(scope,arg)
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
  def compile_break(scope, value = nil)
    br = scope.break_label
    @e.comment("BREAK")

    if br
      # Simple break to a label (e.g., from a while loop)
      # Compile the value if present and put it in %eax
      if value
        ret = compile_eval_arg(scope, value)
        @e.movl(ret, :eax) if ret != :eax
      end
      @e.jmp(br)
    else
      # Handling lexical break from block/proc's.

      # First, load the target stackframe from __env__[0]
      ret = compile_eval_arg(scope,[:index,:__env__,0])
      @e.movl(ret,:eax) if ret != :eax

      # Now compile and save break value in %ecx AFTER loading __env__
      # This avoids register conflicts during __env__ compilation
      if value
        @e.pushl(:eax)  # Save target stackframe on stack temporarily
        ret = compile_eval_arg(scope, value)
        @e.save_result(ret)
        @e.movl(:eax, :ecx)  # Save break value in %ecx
        @e.popl(:eax)  # Restore target stackframe to %eax
      end

      # Jump to test first to avoid doing leave twice
      l_test = @e.get_local + "_test"
      l_done = @e.get_local + "_done"
      @e.jmp l_test

      # Loop body: skip return address and continue
      l_loop = @e.local
      @e.addl(4,:esp)

      # Test: unwind one frame and check if we're at target
      @e.local(l_test)
      @e.leave
      @e.cmpl(:eax, :ebp)
      @e.jnz l_loop

      # Done unwinding
      @e.local(l_done)

      # Restore break value from %ecx to %eax if we had one
      if value
        @e.movl(:ecx, :eax)
      end

      @e.movl("-4(%ebp)",:ebx)
      @e.ret
    end
    @e.evict_all
    return Value.new([:subexpr])
  end
end
