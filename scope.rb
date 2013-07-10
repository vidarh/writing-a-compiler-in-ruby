
# Holds globals, and (for now at least), global constants.
# Note that Ruby-like "constants" aren't really - they are "assign-once"
# variables. As such, some of them can be treated as true constants
# (because their value is known at compile time), but some of them are
# not. For now, we'll treat all of them as global variables.
class GlobalScope
  attr_accessor :globals
  attr_reader :class_scope

  def initialize(offsets)
    @vtableoffsets = offsets
    @globals = Set.new
    @class_scope = ClassScope.new(self,"Object",@vtableoffsets)
  end

  # Returns an argument within the global scope, if defined here.
  # Otherwise returns it as an address (<tt>:addr</tt>)
  def get_arg(a)
    return [:global, a] if @globals.member?(a)
    return [:possible_callm, a] if a && !(?A..?Z).member?(a.to_s[0]) # Hacky way of excluding constants
    return [:addr, a]
  end
end


# Function Scope.
# Holds variables defined within function, as well as all arguments
# part of the function.
class FuncScope
  attr_reader :func

  def initialize(func)
    @func = func
  end


  def rest?
    @func ? @func.rest? : false
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
end


# Local scope.
# Is used when local variables are defined via <tt>:let</tt> expression.
class LocalVarScope
  def initialize(locals, next_scope)
    @next = next_scope
    @locals = locals
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

# The purpose of this scope is mainly to prevent
# (call foo) in an escaped s-expression from being
# rewritten to (callm self foo) when inside a class
# definition - this rewrite is ok for non-escaped
# code, but for embedded s-expressions the purpose
# is to have explicit control  over the low level
# constructs
class SexpScope
  def initialize(next_scope)
    @next = next_scope
  end

  def rest?
    @next.rest?
  end

  def get_arg(a)
    arg = @next.get_arg(a)
    if arg[0] == :possible_callm
      arg[0] = :addr
    end
    arg
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
  # slot 0 is reserved for the vtable pointer for _all_ classes.
  # slot 1 is reserved for @instance_size for objects of class Class
  CLASS_IVAR_NUM = 2

  def initialize(next_scope, name, offsets)
    @next = next_scope
    @name = name
    @vtable = {}
    @vtableoffsets = offsets
    @instance_vars = [:@__class__] # FIXME: Do this properly
    @class_vars = {}
  end

  def class_scope
    self
  end

  def rest?
    false
  end

  def add_ivar(a)
    @instance_vars << a.to_sym if !@instance_vars.include?(a.to_sym)
  end

  def instance_size
    @instance_vars.size
  end


  # Returns an argument within a class scope.
  # First, check if argument is class or instance variable.
  # If argument is not defined within class scope, check next (outer) scope.
  # If both fails, the argument is an adress (<tt>:addr</tt>).
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
      cvar = "__classvar__#{@name}__#{instance_var}"
      return [:cvar, cvar.to_sym] # -> e.g. __classvar__Foo__varname
    end

    # instance variables.
    # if it starts with a single "@", it's a instance variable.
    if a.to_s[0] == ?@ or @instance_vars.include?(a)
      offset = @instance_vars.index(a)
      add_ivar(a) if !offset
      offset = @instance_vars.index(a)
      return [:ivar, offset]
    end

    # if not in class scope, check next (outer) scope.
    n =  @next.get_arg(a) if @next

    return [:possible_callm, n[1]] if n && !(?A..?Z).member?(a.to_s[0]) # Hacky way of excluding constants
    return n if n

    # if none works up to here, it must be an adress.
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


  # Adds a given name / identifier to the classes vtable, if not yet added.
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
    v.offset = @vtableoffsets.alloc_offset(name) if !v.offset
    return v
  end


  # Sets a given vtable entry (identified by <tt>name</tt>)
  # with the given <tt>realname</tt> and function <tt>f</tt>
  def set_vtable_entry(name, realname, f)
    v = add_vtable_entry(name)
    v.realname = realname
    v.function = f
  end
end

