
# In MRI Symbol objects are "type tagged" integers. That is, they are not
# real objects at all, rather each symbol is represented by a specific
# 32 bit value, and those values can be identified as symbols by looking
# for a specific bit-pattern in the least significant byte.
#
# This has the advantage of saving space - no actual instances need to be
# constructed. In this instance, however, it creates a lot of complication,
# by requiring the type tags to be checked on each and every method call.
#
# For this reason we will, at least for now, avoid it.
#
# Instead we will keep a hash table of allocated symbols, which we will
# use to return the same object for the same symbol literal

class Symbol
  # Using class instance var instead of class var
  # because the latter is not properly implemented yet,
  # though in this case it may not make a difference
  @symbols = {}

  # FIXME: Should be private, but we don't support that yet
  def initialize(name)
    @name = name
  end

  def to_s
    @name
  end

  # FIXME
  # The compiler should turn ":foo" into Symbol.__get_symbol("foo").
  # Alternatively, the compiler can do this _once_ at the start for
  # any symbol encountered in the source text, and store the result.
  def self.__get_symbol(name)
    sym = @symbols[name]
    if !sym
      sym = Symbol.new(name)
    end
    sym
  end
end

