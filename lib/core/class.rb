# CLASS OBJECT METADATA SLOTS (fixed offsets, read below by hardcoded index). These must stay
# in sync with ClassScope::CLASS_IVAR_NUM (currently 6) and with Object's ivar count, because a
# Class object's metadata is laid out right after Object's ivars:
#   slot 0: @__class__ / vtable ptr   slot 1: @instance_size   slot 2: @name
#   slot 3: superclass                slot 4: subclasses        slot 5: next_sibling
# To add an ivar to Object (see lib/core/object.rb), every one of these shifts up by one. The
# hardcoded uses are scattered as BOTH `(index <ob> N)` AND bare CLASS_IVAR_NUM literals (e.g.
# `(assign i 6)` below skips the metadata slots) -- all must be found and bumped together, or
# the bootstrap silently corrupts. Immediates (Integer etc.) are type-tagged with no slots.
#
# size <= ssize *always* or something is severely wrong.
%s(defun __new_class_object (size superclass ssize classob)
  (let (ob i)
   (if (eq classob 0) (assign classob Class))
   (assign ob (__array size))
   (assign i 6) # Skips the initial instance vars
 #  %s(printf "class object: %p (%d bytes) / Class: %p / super: %p / size: %d\n" ob size Class superclass ssize)
  (while (lt i ssize) (do
       (assign (index ob i) (index superclass i))
       (assign i (add i 1))
  ))
  (while (lt i size) (do
       # Installing a pointer to a thunk to method_missing
       # that adds a symbol matching the vtable entry as the 
       # first argument and then jumps straight into __method_missing
       (assign (index ob i) (index __base_vtable i))
       (assign i (add i 1))
  ))
  (assign (index ob 0) classob)
  (assign (index ob 3) superclass)
# Sub-classes
  (assign (index ob 4) 0) 
  (if (eq superclass 0)
     (assign (index ob 5) 0)
     (do
        # Link in as subclass:
        (assign (index ob 5) (index superclass 4))
        (assign (index superclass 4) ob)
        )
)
  ob
))

# # __set_vtable
#
# Set the vtable entry. If a subclass has *not*
# overridden a method, then propagate the override 
# downwards.
#
#  ---
#
# Most of this could be turned into pure Ruby. The
# code is roughly equivalent to this "pseudo-Ruby":
#
#```ruby
#   p = vtable.subclasses
#   while p
#      if p[off] == vtable[off]; __set_vtable(p,off,ptr); end
#      p = p.next_sibling
#   end
#   vtable[off] = ptr
#```
#
%s(defun __set_vtable (vtable off ptr)
   (let (p)
    (assign p (index vtable 4))
    (while (sexp p)
       (do
          (if (eq (index p off) (index vtable off)) (__set_vtable p off ptr))
          (assign p (index p 5))
       )
    )
  (assign (index vtable off) ptr)
))

# __alias_method_runtime
#
# Runtime alias implementation - copies function pointer from old to new offset.
# vtable: the class vtable
# new_off: offset for the new alias name
# old_off: offset for the existing method
#
# Simply copies vtable[old_off] to vtable[new_off]. If the old method doesn't
# exist (points to method_missing), the alias will also point to method_missing,
# which will fail at runtime when called (correct Ruby behavior).
#
%s(defun __alias_method_runtime (vtable new_off old_off)
  (let (ptr)
    (assign ptr (index vtable old_off))
    (__set_vtable vtable new_off ptr)
  )
)

# __include_module
#
# Copy methods from a module to a class.
# Only copies vtable slots that are still uninitialized
# (pointing to method_missing thunks in __base_vtable).
#
# This ensures that:
# - Methods defined in the class are not overwritten
# - Multiple includes work correctly (first defined wins)
#
%s(defun __include_module (klass mod)
   (let (i)
    # Skip if module is not yet initialized (0/null)
    # This can happen if a class tries to include a module that's defined later
    (if (eq mod 0) (return 0))

    (assign i 6)  # Skip the initial instance vars (slots 0-5)
    (while (lt i __vtable_size)
       (do
          # Only copy if the class slot is still uninitialized. __set_vtable (rather than a
          # plain assign) propagates the included method to already-created subclasses, the
          # same way a normal `def` does.
          (if (eq (index klass i) (index __base_vtable i))
             (__set_vtable klass i (index mod i))
          )
          (assign i (add i 1))
       )
    )
   )
)


# FIXME: Note that Class incorrectly does *NOT* inherit
# from Object at this stage.
#
class Class

  # We first introduce three "low-level" methods that should eventually be
  # hidden from normal users somehow. These are necessary in order to implement
  # functionality that might otherwise  trigger infinite recursion during object
  # creation, most specifically conversion of splat arrays into genuine Ruby-arrays.
  #
  # Sub-classes that need to be able to do basic "under-the-hood" bootstrapping
  # of instances without creating any objects should implement <tt>__initialize</tt>
  #
  # See Array#__initialize
  #
  def __initialize
  end

  # Clients that need to be able to allocate a completely clean-slate empty
  # object, should call <tt>allocate</tt>.
  #
  def allocate
    %s(assign ob (__array @instance_size))
    %s(if (eq ob 0) (do
      (printf "FATAL: Failed to allocate object of size %ld, class %s\n" (mul 4 @instance_size) (index self 2))
      (div 0 0)
    ))
    %s(assign (index ob 0) self)
    ob
  end

  # Clients that want to be able to create and initialize a basic version of
  # an object without normal initializtion should call <tt>__new</tt>. See
  # <tt>__splat_to_array</tt>
  #
  def __new
    ob = allocate
    ob.__initialize
    ob
  end

  # FIXME: Optimizing this will shave massively off __splat_to_Array calls.
  def new *__copysplat
    ob = allocate
    ob.initialize(*__copysplat)
    ob
  end

  def name
    %s(__get_string @name)
  end

  alias to_s name
  alias inspect name

  def !=  other
    !(self == other)
  end

  # FIXME: The "if" is a workaround due to bootstrap
  # issues which get any classes that get initialized before
  # Object set up with the superclass pointer set to 0 at
  # the moment. A proper fix is needed
  def superclass
    %s(if (index self 3) (index self 3) Object)
  end

  # The ancestry chain of self. Walks the superclass links; included modules are not tracked here
  # (Class#include copies the vtable without recording the module), so this returns the class chain
  # only -- enough that Module#ancestors is not a missing method (which raised at describe-level in
  # specs and, being unrescued, exited -> tgc_sweep abort).
  def ancestors
    result = []
    k = self
    while k
      result << k
      nxt = k.superclass
      break if nxt == k
      k = nxt
    end
    result
  end

  # The method names available on instances of this class/module. Iterates the global name->vtable-offset
  # map and keeps names whose slot in THIS class holds a real method (outside the shared thunk range) --
  # the same test Object#respond_to? uses. `include_super` is accepted but not yet honoured (inherited
  # methods are always included, since the vtable copies them down). Returns Symbols.
  def instance_methods(include_super = true)
    result = []
    m = Class.method_to_voff
    names = m.keys
    i = 0
    n = names.length
    while i < n
      name = names[i]
      voff = m[name]
      real = false
      %s(assign raw (callm voff __get_raw))
      %s(assign ptr (index self raw))
      %s(if (lt ptr __vtable_thunks_start) (assign real true))
      %s(if (gt ptr __vtable_thunks_end) (assign real true))
      result << name if real
      i = i + 1
    end
    result
  end

  # True if instances of this class/module respond to `name` (a real method in this class's vtable,
  # outside the shared thunk range). Visibility is not tracked, so public_method_defined? is the same.
  def method_defined?(name)
    name = name.to_sym if name.is_a?(String)
    voff = Class.method_to_voff[name]
    return false if voff.nil?
    real = false
    %s(assign raw (callm voff __get_raw))
    %s(assign ptr (index self raw))
    %s(if (lt ptr __vtable_thunks_start) (assign real true))
    %s(if (gt ptr __vtable_thunks_end) (assign real true))
    real
  end

  alias public_method_defined? method_defined?

  # FIXME
  # &block will be a "bare" %s(lambda) (that needs to be implemented),
  # define_method needs to attach that to the vtable (for now) and/or
  # to a hash table for "overflow" (methods lacking vtable slots).
  # This requires a painful decision:
  #
  # - To type-tag Symbol or not to type-tag
  #
  # It also means adding a function to look up a vtable offset from
  # a symbol, which effectively means a simple hash table implementation
  #
  # Runtime fallback no-op. Most define_method calls are rewritten to a real `def` at compile time
  # (transform.rb rewrite_define_method); forms it can't statically rewrite (exotic block params, a dynamic
  # body) reach here. Accept the optional body arg (`define_method(:name, proc)`) so it doesn't raise
  # "wrong number of arguments", and do nothing rather than crash while a fixture loads.
  def define_method(sym, body = nil, &block)
    nil
  end

  # FIXME: Should handle multiple symbols
  def attr_accessor sym
    attr_reader sym
    attr_writer sym
  end
  
  def attr_reader sym
    %s(printf "attr_reader %s\n" (callm (callm sym to_s) __get_raw))
    define_method sym do
#       %s(ivar self sym) # FIXME: Create the "ivar" s-exp directive.
      nil
    end
  end

  def attr_writer sym
    %s(printf "attr_writer %s\n" (callm (callm sym to_s) __get_raw))
    # FIXME: Ouch: Requires both String, string interpolation and String#to_sym to
    # be implemented on top of define_method and "ivar"
    define_method "#{sym.to_s}=".to_sym do |val|
#      %s(assign (ivar self sym) val)
    end
  end

  # attr - single name creates reader, name + true creates accessor
  def attr name, setter=false
    if setter
      attr_accessor name
    else
      attr_reader name
    end
  end

  # prepend - insert module methods before class methods
  # Stub: For now, just include it (same as append)
  def prepend mod
    include mod
  end

  # class_eval - evaluate block in class context
  # Stub: Just yield the block
  def class_eval &block
    if block
      block.call
    end
  end

  # module_function - make instance methods also available as module methods
  # Stub: No-op for now
  def module_function *names
    nil
  end

  # extend - add module methods to an object's singleton class
  # Stub: No-op for now (proper implementation needs singleton class support)
  def extend mod
    nil
  end

  # Check if a module is included by checking if module's methods are in class vtable
  # This is an approximation - it checks if the methods match, not if include was actually called
  # But it's good enough for most specs and avoids bootstrap issues
  def include?(mod)
    # Handle null module
    %s(if (eq mod 0) (return false))

    # Check if at least one method from the module is present in this class
    # by comparing vtable slots
    %s(let (i found)
      (assign i 6)  # Start after instance variable slots
      (assign found 0)
      (while (and (eq found 0) (lt i __vtable_size)) (do
        # If module has a method (not __base_vtable) and class has same method
        (if (and
              (ne (index mod i) (index __base_vtable i))
              (eq (index self i) (index mod i)))
          (assign found 1)
        )
        (assign i (add i 1))
      ))
      # Convert 0/1 to false/true
      (if (eq found 1) (return true) (return false))
    )
  end

  # Include a module into this class
  # Calls __include_module to copy vtable entries
  def include(mod)
    %s(__include_module self mod)
  end

  # Visibility modifiers - stubbed as no-ops for now
  # These need to be implemented properly to track method visibility
  def private *args
    nil
  end

  def protected *args
    nil
  end

  def public *args
    nil
  end

end

%s(assign (index Class 0) Class)
%s(assign (index Class 2) "Class")

