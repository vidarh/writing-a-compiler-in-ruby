
require 'delegate'

# Used to hold a possiby-typed value
# Currently, valid values for "type"
# are :object or nil.
class Value < SimpleDelegator
  attr_reader :type

  def initialize ob, type = nil
    super(ob)
    @type = type
  end

  # Explicit []: get_arg returns a Value wrapping an instruction node ([:int, x], [:ivar, ...]), and
  # compile_eval_arg reads args[0]/args[1] on it for every compiled expression. Without this, each index
  # went through SimpleDelegator#method_missing (a dispatch that collects a *args Array) -- one of the
  # hottest codegen allocators, on both hosts. Delegates straight to the wrapped object instead. `len=nil`
  # acts as the sentinel so the common single-index form allocates nothing while [i,len] / [range] still work.
  def [](i, len = nil)
    len.nil? ? __getobj__[i] : __getobj__[i, len]
  end

  # Evil. Since we explicitly check for Symbol some places
  def is_a?(ob)
    __getobj__.is_a?(ob)
  end
end


