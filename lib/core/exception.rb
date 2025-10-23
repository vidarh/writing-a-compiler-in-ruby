# Exception handler structure
# Stores saved stack state for unwinding
# Similar to how Proc stores function address/environment
class ExceptionHandler
  def initialize
    @saved_ebp = nil      # Saved stack frame pointer
    @handler_addr = nil   # Address of rescue label to jump to
    @rescue_classes = nil # nil = catch all, or Array of classes to catch
    @next = nil           # Next handler in chain
  end

  # Save current stack state
  # Called when setting up begin...rescue
  # handler_addr is the address of the rescue: label (computed by compiler)
  def save_stack_state(handler_addr)
    @handler_addr = handler_addr
    # Save current frame pointer
    %s(assign @saved_ebp (stackframe))
  end

  def saved_ebp
    @saved_ebp
  end

  def handler_addr
    @handler_addr
  end

  def rescue_classes
    @rescue_classes
  end

  def rescue_classes=(classes)
    @rescue_classes = classes
  end

  def next
    @next
  end

  def next=(n)
    @next = n
  end
end

# Exception runtime - manages the exception handler stack
# This is a singleton-like class (using class variables)
class ExceptionRuntime
  # Global exception state
  @@exc_stack = nil           # Top of handler stack
  @@current_exception = nil   # Currently raised exception object

  # Push a handler onto the exception stack
  # Returns the handler for caller to initialize
  def self.push_handler(rescue_classes = nil)
    handler = ExceptionHandler.new
    handler.rescue_classes = rescue_classes
    handler.next = @@exc_stack
    @@exc_stack = handler
    return handler
  end

  # Pop handler from stack
  def self.pop_handler
    if @@exc_stack
      @@exc_stack = @@exc_stack.next
    end
  end

  # Get current handler
  def self.current_handler
    @@exc_stack
  end

  # Raise an exception
  # Unwinds stack by restoring saved %ebp and jumping to handler
  # This is implemented as a low-level function because it needs to
  # manipulate stack and jump directly
  def self.raise(exception_obj)
    @@current_exception = exception_obj

    if @@exc_stack
      handler = @@exc_stack
      @@exc_stack = handler.next  # Pop before jumping

      # TODO: Check if exception matches rescue classes

      # Get the saved stack frame and handler address
      saved_frame = handler.saved_ebp
      handler_addr = handler.handler_addr

      # Restore stack frame and jump to handler
      # This is similar to preturn but jumps to a label instead of returning
      %s(do
        (assign ebp saved_frame)
        (assign ebx (index ebp -4))
        (call handler_addr)
      )
      # Never returns (the call above jumps to rescue handler)
    else
      # Unhandled exception
      %s(printf "Unhandled exception: ")
      msg = exception_obj.to_s
      %s(printf "%s\n" (callm msg __get_raw))
      %s(exit 1)
    end
  end

  # Get current exception (called from rescue block)
  def self.current_exception
    @@current_exception
  end

  # Clear current exception (after rescue handles it)
  def self.clear
    @@current_exception = nil
  end
end

# Exception classes
class Exception
  def initialize(msg = nil)
    @message = msg
  end

  def message
    @message
  end

  def to_s
    if @message
      @message
    else
      self.class.to_s
    end
  end
end

class StandardError < Exception
end

class TypeError < StandardError
end

class NoMethodError < StandardError
end

class ArgumentError < StandardError
end

class FrozenError < StandardError
end

class RangeError < StandardError
end

class ZeroDivisionError < StandardError
end

class RuntimeError < StandardError
  def initialize(msg = "RuntimeError")
    @message = msg
  end
end

class FloatDomainError < StandardError
end
