
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

  # Runtime constant lookup - stub implementation
  # Used when constant cannot be resolved statically
  def __const_get(parent_name, const_name)
    STDERR.puts "Runtime constant lookup not implemented: #{parent_name}::#{const_name}"
    raise "NameError: uninitialized constant #{parent_name}::#{const_name}"
  end

  # Runtime constant lookup on an object - stub implementation
  def __const_get_on(parent_obj, const_name)
    STDERR.puts "Runtime constant lookup not implemented: <object>::#{const_name}"
    raise "NameError: uninitialized constant #{const_name}"
  end

  # Runtime constant lookup in global scope - stub implementation
  def __const_get_global(const_name)
    STDERR.puts "Runtime constant lookup not implemented: #{const_name}"
    raise "NameError: uninitialized constant #{const_name}"
  end

  # Runtime require - stub implementation
  # All requires must be resolved at compile time in this AOT compiler
  # Raise LoadError if require is called at runtime
  def require(path)
    raise LoadError.new("Dynamic require not supported in AOT compiler: #{path}")
  end

  # Runtime require_relative - stub implementation
  def require_relative(path)
    raise LoadError.new("Dynamic require_relative not supported in AOT compiler: #{path}")
  end
end
