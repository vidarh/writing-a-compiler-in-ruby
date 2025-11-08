
class Kernel
  def puts s
    %s(puts (index s 1))
  end

  # Raise an exception
  # Simplified version - just handles string messages for now
  def raise(msg)
    exc = RuntimeError.new(msg)
    $__exception_runtime.raise(exc)
    # Never returns
  end

  # Alias for raise
  def fail(exception_or_msg = nil)
    raise(exception_or_msg)
  end

  # Infinite loop - executes block repeatedly until break
  def loop
    while true
      yield
    end
  end
end
