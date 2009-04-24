
# Holds globals, and (for now at least), global constants.
# Note that Ruby-like "constants" aren't really - they are "assign-once"
# variables. As such, some of them can be treated as true constants
# (because their value is known at compile time), but some of them are
# not. For now, we'll treat all of them as global variables.
class GlobalScope
  attr_accessor :globals

  def initialize
    @globals = Set.new
  end

  def get_arg(a)
    return [:global, a] if @globals.member?(a)
    return [:addr, a]
  end
end

class FuncScope
  def initialize(func, next_scope = nil)
    @func = func
    @next = next_scope
  end

  def rest?
    @func ? @func.rest? : false
  end

  def get_arg(a)
    a = a.to_sym
    if @func
      arg = @func.get_arg(a)
      return arg if arg
    end
    return @next.get_arg(a) if @next
    return [:addr, a]
  end
end


class LocalVarScope
  def initialize(locals, next_scope)
    @next = next_scope
    @locals = locals
  end

  def rest?
    @next ? @next.rest? : false
  end

  def get_arg(a)
    a = a.to_sym
    return [:lvar, @locals[a] + (rest? ? 1 : 0)] if @locals.include?(a)
    return @next.get_arg(a) if @next
    return [:addr, a] # Shouldn't get here normally
  end
end


VTableEntry = Struct.new(:name, :realname, :offset, :function)

# Need a global list of vtable offsets since
# we can't usually statically determine what class
# an object belongs to.
class VTableOffsets
  def initialize
    @vtable = {}
    @vtable_max = 1 # Start at 1 since offset 0 is reserved for the vtable pointer for the Class object
    # Then we insert the "new" method.
    alloc_offset(:new)
    # __send__ is our fallback if no vtable
    # offset was found, so it *must* have a slot
    alloc_offset(:__send__)
  end

  def clean_name(name)
    name = name[1] if name.is_a?(Array) # Handle cases like self.foo => look up he offset for "foo"
    name = name.to_sym
  end

  def alloc_offset(name)
    name = clean_name(name)
    if !@vtable[name]
      @vtable[name] = @vtable_max
      @vtable_max += 1
    end
  end

  def get_offset(name)
    return @vtable[clean_name(name)]
  end

  def max
    @vtable_max
  end
end

class ClassScope
  attr_reader :name, :vtable

  def initialize(next_scope, name, offsets)
    @next = next_scope
    @name = name
    @vtable = {}
    @vtableoffsets = offsets
  end

  def rest?
    false
  end

  def get_arg(a)
    return @next.get_arg(a) if @next
    return [:addr, a]
  end

  def klass_size
    @vtableoffsets.max * Emitter::PTR_SIZE
  end

  def add_vtable_entry(name)
    # FIXME: If "name" is an array, the first element specified the
    # class object to add the vtable entry to. If it is "self"
    # it means adding the entry to the meta class (and possibly creating
    # the meta class). If it is not "self" we need to generate code
    # for adding this method, as the class object may be dynamically
    # determined. The vtable offset would be determined based on name[1] in
    # this case.
    @vtable[name] ||= VTableEntry.new
    v = @vtable[name]
    v.name = name.to_s
    v.offset = @vtableoffsets.get_offset(name) if !v.offset
    return v
  end

  def set_vtable_entry(name, realname, f)
    v = add_vtable_entry(name)
    v.realname = realname
    v.function = f
  end
end

