# Binding class - represents an execution context
# Stub implementation for linking compatibility

class Binding
  # Stub methods - don't need to be functional for now
  # Just need to exist for linking

  def eval(code)
    # FIXME: Not implemented - would need to compile and execute code
    nil
  end

  def local_variables
    # FIXME: Not implemented - would need to track local variable names
    []
  end
end

# TOPLEVEL_BINDING - the binding of the top-level context
# Create a stub instance for now
TOPLEVEL_BINDING = Binding.new
