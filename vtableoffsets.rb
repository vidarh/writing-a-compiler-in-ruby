

VTableEntry = Struct.new(:name, :realname, :offset, :function)

# Need a global list of vtable offsets since
# we can't usually statically determine what class
# an object belongs to.
class VTableOffsets
  attr_reader :vtable

  def initialize
    @vtable = {}
    # Start at CLASS_IVAR_NUM to allow convenient allocation of ivar space for the Class object
    @vtable_max = ClassScope::CLASS_IVAR_NUM
    # Then we insert the "new" method.
    alloc_offset(:new)
    # __send__ is our fallback if no vtable
    # offset was found, so it *must* have a slot
    alloc_offset(:__send__)

    # Must be defined to prevent non-terminating recursion
    # in Compiler#compile_callm
    alloc_offset(:__get_symbol)
  end


  # Returns the given name as a Symbol.
  # If the name is an array, return the converted first element
  # of the array as the name.
  def clean_name(name)
    name = name[1] if name.is_a?(Array) # Handle cases like self.foo => look up the offset for "foo"
    name = name.to_sym
  end


  # If the given name isn't saved to the vtable yet,
  # increase <tt>@vtable_max</tt> and save the name to the vtable
  # with the new <tt>@vtable_max</tt> as the value.
  def alloc_offset(name)
    name = clean_name(name)
    if !@vtable[name]
      @vtable[name] = @vtable_max
      @vtable_max += 1
    end
    @vtable[name]
  end


  # Returns the vtable offset for a given name.
  def get_offset(name)
    return @vtable[clean_name(name)]
  end


  # Returns the current max value for the vtable.
  def max
    @vtable_max
  end
end
