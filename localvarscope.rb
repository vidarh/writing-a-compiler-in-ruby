
# Local scope.
# Is used when local variables are defined via <tt>:let</tt> expression.
class LocalVarScope < Scope
  attr_accessor :eigenclass_scope
  attr_reader :stack_size

  def initialize(locals, next_scope, eigenclass_scope = false)
    @next = next_scope
    @locals = locals
    @eigenclass_scope = eigenclass_scope
    # Track stack size: matches the "s = vars.size + 2" calculation in let()
    # But if locals is empty, let() doesn't allocate any stack, so stack_size is 0
    @stack_size = locals.size > 0 ? (locals.size + 2) : 0
  end

  def method
    @next ? @next.method : nil
  end

  def rest?
    @next ? @next.rest? : false
  end

  # Return the stack offset contribution of this LocalVarScope
  # This is used by nested LocalVarScopes to calculate their variable offsets
  def lvaroffset
    offset = @stack_size
    offset += @next.lvaroffset if @next
    offset
  end

  # Returns an argument within the current local scope.
  # If the passed argument isn't defined in this local scope,
  # check the next (outer) scope.
  # Finally, return it as an adress, if both doesn't work.
  def get_arg(a)
    a = a.to_sym
    if @locals.include?(a)
      # Our local variable: use index + rest adjustment + parent's lvaroffset
      # Parent's lvaroffset includes cumulative LocalVarScope offsets and stops at FuncScope
      return [:lvar, @locals[a] + (rest? ? 1 : 0) + @next.lvaroffset]
    end

    # Variable in outer scope: delegate to parent (offset already correct relative to %ebp)
    return @next.get_arg(a) if @next
    return [:addr, a]
  end

  # Delegate to next scope to find ClassScope/ModuleScope
  # LocalVarScope is not a class scope, so traverse to find one
  def class_scope
    return @next.class_scope if @next
    return self
  end

  # Delegate to parent scope for name (module/class prefix)
  # This ensures constants defined in local scopes inside modules/classes get the correct prefix
  def name
    @next ? @next.name : ""
  end
end
