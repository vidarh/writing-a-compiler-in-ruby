require 'emitter'
require 'vtableoffsets'


# Holds name of class, vtable for methods defined within the class
# as well as all defined instance & class variables.
class ModuleScope < Scope
  # class name,
  # method v-table,
  # instance variables
  # and class variables
  attr_reader :vtable, :instance_vars, :class_vars
  attr_reader :vtableoffsets

  # This is the number of instance variables allowed for the class
  # Class, and is used for bootstrapping. Note that it could be
  # determined by the compiler checking the actual class implementation,
  # so this is a bit of a copout.
  #
  # slot 0 is reserved for the vtable pointer for _all_ classes.
  # slot 1 is reserved for @instance_size for objects of class Class
  # slot 2 is reserved for @name
  # slot 3 is reserved for the superclass pointer
  # slot 4 is reserved for subclasses
  # slot 5 is reserved for next_sibling
  CLASS_IVAR_NUM = 6

  def initialize(next_scope, name, offsets, superclass = nil)
    @next = next_scope
    @superclass = superclass
    @name = name
    @vtable = {}
    @vtableoffsets = offsets
    @ivaroff = @superclass ? @superclass.instance_size : 0
    @instance_vars = !@superclass ? [:@__class__]  : [] # FIXME: Do this properly
    @class_vars = {}

    @constants = {}

    @modules = []
  end

  def include_module(m)
    @modules << m
  end

  def find_constant(c)
    const = @constants[c]
    return const if const
    return @next.find_constant(c) if @next
    return nil
  end

  def prefix
    return "" if !@next
    n = @next.name
    return "" if n.empty?
    return n + "__"
  end

  def local_name
    @name
  end

  def name
    prefix + @name.to_s
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

  def add_constant(c, v = true)
    @constants[c] = v
  end

  def instance_size
    @instance_vars.size + @ivaroff
  end


  def get_constant(a)
    if @constants.member?(a.to_sym)
      return [:global,name + "__" + a.to_s]
    else
      @modules.each do |m|
        n = m.get_constant(a)
        return n if n
      end

      if @superclass
        n = @superclass.get_constant(a)
        return n if n && n[0] != :addr
      end

      return @next.get_arg(a)
    end
  end

  def get_class_var(a)
    instance_var = a.to_s[2..-1].to_sym # save without "@@"
    is_new = !@class_vars[a]

    cvar = "__classvar__#{@name}__#{instance_var}"

    if is_new
      @class_vars[a] = instance_var
      add_global(cvar)
    end

    return [:global, cvar.to_sym] # -> e.g. __classvar__Foo__varname
  end

  def get_instance_var(a)
    offset = @instance_vars.index(a)
    add_ivar(a) if !offset
    offset = @instance_vars.index(a)

    # This will show the name of the current class, the superclass name, the instance variable 
    # name, the offset of the instance variable relative to the current class "base", and the
    # instance variable offset for the current class which comes in quite handy when debugging
    # object layout:
    #
    # STDERR.puts [:ivar, @name, @superclass ? @superclass.name : "",a, offset, @ivaroff].inspect
    return [:ivar, offset + @ivaroff]
  end

  # Returns an argument within a class scope.
  # First, check if argument is class or instance variable.
  # If argument is not defined within class scope, check next (outer) scope.
  # If both fails, the argument is an adress (<tt>:addr</tt>).
  def get_arg(a)
    # Handle self
    if a.to_sym == :self
      return [:global,name]
    end

    as = a.to_s

    return get_constant(a)  if (?A..?Z).member?(as[0])
    return get_class_var(a) if as[0..1] == "@@" or @class_vars.include?(a)
    return get_instance_var(a) if a.to_s[0] == ?@ or @instance_vars.include?(a)

    # if not in class scope, check next (outer) scope.
    n =  @next.get_arg(a) if @next

    return n if n[0] == :global # Prevent e.g. "true" from being treated as method call
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



class ClassScope < ModuleScope
end
