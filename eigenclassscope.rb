# EigenclassScope - ClassScope for eigenclass method definitions
#
# Sits between LocalVarScope and FuncScope to provide a ClassScope
# for method registration while allowing variable resolution to
# fall through to @next.

class EigenclassScope < ClassScope
  # Override lvaroffset to delegate to @next
  # This is needed so LocalVarScope offset calculations work correctly
  # when EigenclassScope is in the middle of the scope chain
  def lvaroffset
    @next ? @next.lvaroffset : 0
  end

    # Defer to parents class variable.
  # FIXME: This might need to actually dynamically
  # look up the superclass?
  def get_class_var(var)
    @next.get_class_var(var)
  end

  def get_arg(var, save = false)
    if var == :self
      return @next.get_arg(var, save)
    end
    super(var, save)
  end
end
