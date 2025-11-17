
class Kernel
  def puts s
    %s(puts (index s 1))
  end

  # Raise an exception
  # Handles both String messages and Exception objects
  def raise(msg_or_exc)
    if msg_or_exc.is_a?(StandardError)
      exc = msg_or_exc
    else
      exc = RuntimeError.new(msg_or_exc)
    end
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

  # Exit the program with given code
  def exit(code)
    %s(exit (callm code __get_raw))
  end

  # Execute a shell command (stub - not implemented)
  def system(cmd)
    raise "system() not implemented - backtick/command execution not supported"
  end

  # Convert argument to Array
  def Array(arg)
    if arg.respond_to?(:to_ary)
      arg.to_ary
    elsif arg.respond_to?(:to_a)
      arg.to_a
    else
      [arg]
    end
  end
end
