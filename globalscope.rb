
# Holds globals, and (for now at least), global constants.
# Note that Ruby-like "constants" aren't really - they are "assign-once"
# variables. As such, some of them can be treated as true constants
# (because their value is known at compile time), but some of them are
# not. For now, we'll treat all of them as global variables.
class GlobalScope < Scope
  attr_accessor :globals
  attr_reader :class_scope

  def initialize(offsets)
    @vtableoffsets = offsets
    @globals = Set.new
    @class_scope = ClassScope.new(self,"Object",@vtableoffsets,nil)

    # Despite not following "$name" syntax, these are really global constants.
    @globals << :false
    @globals << :true
    @globals << :nil
  end

  def rest?
    false
  end

  # Returns an argument within the global scope, if defined here.
  # Otherwise returns it as an address (<tt>:addr</tt>)
  def get_arg(a)
    return [:global, a] if @globals.member?(a)
    return [:possible_callm, a] if a && !(?A..?Z).member?(a.to_s[0]) # Hacky way of excluding constants
    return [:addr, a]
  end

  def name
    ""
  end

  def instance_size
    0
  end

  def lvaroffset
    0
  end
end
