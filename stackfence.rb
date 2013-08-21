
class Compiler

  # If @stackfence is set, calling this method with a block
  # will result in a pseudo-random value getting pushed onto
  # the stack, and on return from the block, that value is
  # compared against the top of the stack. If a match if found,
  # all is well and the value is removed from the stack.
  #
  # Otherwise `trace` is called (FIXME: and a way of forcing trace
  # output needs to be added) with an error message. 
  #
  # This provides some validation both that the stack is not
  # pushed/popped unevenly, and that values are not overwritten.
  #
  def stackfence
    if !@stackfence
      return yield
    end

    # Note: We don't care if this value is all that random.
    val = (rand * (2**32)).floor
    @e.pushl(val)
    r = yield
    @e.cmpl(val,"(#{@e.sp.to_s})")
    l = @e.get_local
    @e.jz(l)
    trace(nil,"ERROR: Stack fence violation. Expected 0x#{val.to_s(16)}",:force)
    @e.local(l)
    @e.addl(4,@e.sp)
    r
  end

end
