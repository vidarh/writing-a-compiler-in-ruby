
# Holds globals, and (for now at least), global constants.
# Note that Ruby-like "constants" aren't really - they are "assign-once"
# variables. As such, some of them can be treated as true constants
# (because their value is known at compile time), but some of them are
# not. For now, we'll treat all of them as global variables.
class GlobalScope < Scope
  attr_reader :class_scope, :globals

  def initialize(offsets)
    @vtableoffsets = offsets
    @globals = {}
    @class_scope = ClassScope.new(self,"Object",@vtableoffsets,nil)

    # Despite not following "$name" syntax, these are really global constants.
    @globals[:false] = true
    @globals[:true]  = true
    @globals[:nil]   = true

    # Special "built-in" globals with two-character names starting with $
    # that we need to expand to something else.
    @aliases = {
      :"$:" => "LOAD_PATH",
      :"$0" => "__D_0"
    }
  end

  def add_global(c)
    @globals[c] = true
  end

  def add_constant(c,v = true)
    @globals[c] = v
  end

  def find_constant(c)
    @globals[c]
  end

  def rest?
    false
  end

  # Returns an argument within the global scope, if defined here.
  # Otherwise returns it as an address (<tt>:addr</tt>)
  def get_arg(a)
    # Handle $:, $0 etc.
    s = @aliases[a]
    return [:global, s] if s

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

  def include_module m
  end
end
