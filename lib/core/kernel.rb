
class Kernel
  def puts *str
    na = str.length
    if na == 0
      %s(puts "")
      return
    end

    i = 0
    while i < na
      raw = str[i]
      if raw
        raw = raw.to_s
        last = raw[-1]
        raw = raw.__get_raw
        %s(if (ne raw 0) (printf "%s" raw))
        if last
          if last.ord != 10
            %s(puts "")
          end
        else
          %s(puts "")
        end
      else
        %s(puts "")
      end
      i = i + 1
    end
    nil
  end

  # Raise an exception
  # Handles multiple forms:
  # - raise(exception_obj) - raise an existing exception
  # - raise(string) - raise RuntimeError with message
  # - raise(ExceptionClass) - raise exception class with no message
  # - raise(ExceptionClass, message) - raise exception class with message
  # Called by the compiler at a `yield` with no block (transform.rb rewrite_yield). Keeping the message
  # literal HERE (not injected into the AST after rewrite_strconst) means it is compiled to a real String
  # rather than a raw label address (which became a garbage Integer message and corrupted the caller).
  def __raise_no_block
    raise LocalJumpError.new("no block given (yield)")
  end

  def raise(exc_or_msg = nil, msg = nil)
    if exc_or_msg.nil?
      # raise with nil - should re-raise $! but that's handled by compiler
      exc = RuntimeError.new
    elsif exc_or_msg.is_a?(Class)
      # raise ExceptionClass or raise ExceptionClass, message
      if msg
        exc = exc_or_msg.new(msg)
      else
        exc = exc_or_msg.new
      end
    elsif exc_or_msg.is_a?(StandardError)
      # raise existing_exception
      exc = exc_or_msg
    else
      # raise "message" - assume string message
      exc = RuntimeError.new(exc_or_msg)
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
    return to_enum(:loop) if !block_given?
    while true
      yield
    end
  end

  # Kernel#caller(start=1, length=nil) / caller(range) -> the execution stack as an Array of frame
  # strings. Backtraces are not captured (no stack unwinding), so return an empty Array of the correct
  # type; the bare `caller` form is handled by the compiler (also an empty Array).
  def caller(*args)
    []
  end

  # Coerce a path argument to a String the way File/Dir/FileTest methods do: a String passes through,
  # an object with #to_path (e.g. Pathname, or a mock in the specs) is asked for its path, otherwise
  # #to_str is used. Raises TypeError if none applies.
  def __coerce_path(obj)
    return obj if obj.is_a?(String)
    return obj.to_path if obj.respond_to?(:to_path)
    return obj.to_str if obj.respond_to?(:to_str)
    raise TypeError.new("no implicit conversion into String")
  end

  # at_exit { ... } registers a block to run (LIFO) when the program terminates. Returns the block.
  def at_exit(&blk)
    $__at_exit_handlers ||= []
    $__at_exit_handlers.unshift(blk)   # newest first -> handlers run in reverse registration order
    blk
  end

  # Run the registered at_exit handlers exactly once. Called from #exit (and from main's terminating
  # exit, which the compiler routes through #exit). Guarded so a handler that itself calls exit doesn't
  # re-enter. A raising handler is swallowed (its exit code effect is not modelled).
  def __run_at_exit
    return if $__at_exit_running
    $__at_exit_running = true
    handlers = $__at_exit_handlers
    return if handlers.nil?
    handlers.each do |blk|
      blk.call rescue nil
    end
    nil
  end

  # Exit the program with the given status (true -> 0, false -> 1, else the integer), running at_exit
  # handlers first.
  def exit(code = 0)
    __run_at_exit
    code = 0 if code == true
    code = 1 if code == false
    %s(exit (callm code __get_raw))
  end

  # Run a shell command (via /bin/sh -c), wait for it, and return true if it exited 0, false otherwise.
  # Multiple args are space-joined into one shell command. The command STRINGS are held in Ruby locals so
  # the GC does not free the buffers whose raw pointers are passed to execve.
  def system(*args)
    cmdstr = args.join(" ")
    sh = "/bin/sh"
    dashc = "-c"
    status = -1
    %s(do
      (assign kidpid (fork))
      (if (eq kidpid 0)
        (do
          (assign argv (__array 4))
          (assign (index argv 0) (callm sh __get_raw))
          (assign (index argv 1) (callm dashc __get_raw))
          (assign (index argv 2) (callm cmdstr __get_raw))
          (assign (index argv 3) 0)
          (assign envp (__array 1))
          (assign (index envp 0) 0)
          (execve (callm sh __get_raw) argv envp)
          (exit 127))
        (do
          (assign stbuf (__array 4))
          (waitpid kidpid stbuf 0)
          (assign status (__int (index stbuf 0))))))
    # waitpid's status word: exit code is bits 8..15.
    ((status >> 8) & 255) == 0
  end

  # Kernel backticks: run the command and return its stdout as a String (the parser rewrites `cmd` to a
  # call to this).
  def __backtick(cmd)
    io = IO.popen(cmd.to_s, "r")
    out = io.read
    io.close
    out
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

  # Runtime constant lookup in global scope.
  # FIXME: Should look up dynamic constants from a runtime hash / call const_missing.
  def __const_get_global(const_name)
    raise NameError.new("uninitialized constant #{const_name}")
  end

  # Runtime constant assignment in global scope - stub implementation
  # Dynamic constant assignment is not supported in this AOT compiler
  def __const_set_global(const_name, value)
    STDERR.puts "Runtime constant assignment not implemented: #{const_name}"
    raise "NameError: dynamic constant assignment not supported: #{const_name}"
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

  # catch - Catch thrown values
  # Stub: Just yields the block without actual catching
  # Full implementation would require non-local return mechanism
  def catch(tag)
    yield
  end

  # throw - Throw to catch
  # Stub: No-op (does not actually throw)
  # Full implementation would require non-local return mechanism
  def throw(tag, value=nil)
    nil
  end

  # redo - Restart loop iteration
  # Stub: Not implementable without control flow changes
  def redo
    raise RuntimeError.new("redo not supported in current compiler")
  end

  # fixture - mspec test helper: path to a fixture file beside the spec, under a "fixtures/" dir.
  # Called as fixture(__FILE__, name...) -- variadic, NOT arity 1 (the old arity-1 stub crashed every
  # spec that used the standard 2-arg form with "wrong number of arguments"). Under our harness the whole
  # spec is inlined into one temp file, so __FILE__ (dir) points at tmp/, not the real fixtures. run_rubyspec
  # injects $__mspec_spec_dir with the ORIGINAL spec directory; prefer it so data-fixture files resolve.
  def fixture(dir, *args)
    base = $__mspec_spec_dir
    base = File.dirname(dir) if base.nil?
    File.join(base, "fixtures", *args)
  end

  # proc - Create a Proc from a block
  # Ruby's proc { } is equivalent to Proc.new { }
  # The block is implicitly converted to a Proc when passed with &
  # Note: Can't use 'block' as parameter name - it's a compiler keyword
  def proc(&blk)
    blk
  end

  # lambda - Create a lambda from a block
  # lambda { } creates a Proc that enforces arity and returns from itself
  # This stub creates a regular Proc (lambda semantics not fully enforced)
  # Note: Can't use 'block' as parameter name - it's a compiler keyword
  def lambda(&blk)
    blk
  end
end
