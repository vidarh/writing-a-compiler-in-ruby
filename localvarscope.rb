
# Local scope.
# Is used when local variables are defined via <tt>:let</tt> expression.
class LocalVarScope < Scope
  attr_accessor :eigenclass_scope

  def initialize(locals, next_scope, eigenclass_scope = false)
    @next = next_scope
    @locals = locals
    @eigenclass_scope = eigenclass_scope
  end

  def method
    @next ? @next.method : nil
  end

  def rest?
    @next ? @next.rest? : false
  end


  # Returns an argument within the current local scope.
  # If the passed argument isn't defined in this local scope,
  # check the next (outer) scope.
  # Finally, return it as an adress, if both doesn't work.
  def get_arg(a)
    a = a.to_sym
    return [:lvar, @locals[a] + (rest? ? 1 : 0) + @next.lvaroffset] if @locals.include?(a)
    return @next.get_arg(a) if @next
    return [:addr, a] # Shouldn't get here normally
  end
end
