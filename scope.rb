
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
    # Start at CLASS_IVAR_NUM to allow convenient allocation of ivar space for the Class object
    @vtable_max = ClassScope::CLASS_IVAR_NUM
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


# Class scope.
# Holds name of class, vtable for methods defined within the class
# as well as all defined instance & class variables.
class ClassScope
  # class name,
  # method v-table,
  # instance variables
  # and class variables
  attr_reader :name, :vtable, :instance_vars, :class_vars

  # This is the number of instance variables allowed for the class
  # Class, and is used for bootstrapping. Note that it could be
  # determined by the compiler checking the actual class implementation,
  # so this is a bit of a copout.
  # 
  # slot 0 is reserved for the vtable pointer
  CLASS_IVAR_NUM = 2

  def initialize(next_scope, name, offsets)
    @next = next_scope
    @name = name
    @vtable = {}
    @vtableoffsets = offsets
    @instance_vars = [:@__class__] # FIXME: Do this properly
    @class_vars = {}
  end

  def rest?
    false
  end

  def add_ivar(a)
    @instance_vars << a.to_sym
  end

  def instance_size
    @instance_vars.size
  end

  def get_arg(a)
    # Handle self
    if a.to_sym == :self
      return [:global,@name]
    end

    # class variables.
    # if it starts with "@@" it's a classvariable.
    if a.to_s[0..1] == "@@" or @class_vars.include?(a)
      @class_vars[a] ||= a.to_s[2..-1].to_sym # save without "@@"
      instance_var = @class_vars[a]
      return [:cvar, "__classvar__#{@name}__#{instance_var}".to_sym] # -> e.g. __classvar__Foo__varname
    end

    # instance variables.
    # if it starts with a single "@", it's a instance variable.
    if a.to_s[0] == ?@ or @instance_vars.include?(a)
      offset = @instance_vars.index(a)
      add_ivar(a) if !offset
      offset = @instance_vars.index(a)
      return [:ivar, offset]
    end


    return @next.get_arg(a) if @next
    return [:addr, a]
  end

  # Returns the size of a class object.
  # This is a multiple of @vtableoffsets.max, but this
  # is deceiving as the offsets starts at a value that
  # is based on the amount of data needed at the start of
  # the class object as instance variables for the class
  # object.
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

