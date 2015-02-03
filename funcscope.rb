
# Function Scope.
# Holds variables defined within function, as well as all arguments
# part of the function.
class FuncScope < Scope
  attr_reader :func

  def initialize(func)
    @func = func
    @next = @func.scope
  end


  def rest?
    @func ? @func.rest? : false
  end

  def lvaroffset
    @func.lvaroffset
  end


  # Returns an argument within the function scope, if defined here.
  # A function holds it's own scope chain, so if the function doens't
  # return anything, we fall back to just an addr.
  def get_arg(a)
    a = a.to_sym
    if @func
      arg = @func.get_arg(a)
      return arg if arg
    end
    return [:addr, a]
  end

  def method
    @func
  end
end

