
class Compiler

  # Debug instruction, to save registers 
  # 
  def compile_saveregs(scope)
    # First we push the registers on the stack, to ensure they won't get messed up
    # when we allocate memory.

    @e.pushl(:esp)
    @e.pushl(:ebp)
    @e.pushl(:edi)
    @e.pushl(:esi)
    @e.pushl(:edx)
    @e.pushl(:ecx)
    @e.pushl(:ebx)
    @e.pushl(:eax)

    # Allocate memory
    @e.pushl(8)
    @e.call("malloc")
    @e.addl(4,:esp)

    # We're naughty and assume we get memory:
    @e.popl(:ebx)
    @e.movl(:ebx,"(%eax)")
    @e.popl(:ebx)
    @e.movl(:ebx,"4(%eax)")
    @e.popl(:ebx)
    @e.movl(:ebx,"8(%eax)")
    @e.popl(:ebx)
    @e.movl(:ebx,"12(%eax)")
    @e.popl(:ebx)
    @e.movl(:ebx,"16(%eax)")
    @e.popl(:ebx)
    @e.movl(:ebx,"20(%eax)")
    @e.popl(:ebx)
    @e.movl(:ebx,"24(%eax)")
    @e.popl(:ebx)
    @e.movl(:ebx,"28(%eax)")

    Value.new([:subexpr])
  end
end
