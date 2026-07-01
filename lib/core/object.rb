class Object
  # OBJECT INSTANCE LAYOUT (applies to every heap object, since Object is the root):
  #   slot 0: @__class__  -- the class pointer (word 0)
  #   then each class's ivars, allocated in order of first mention, lowest class first.
  #
  # Adding an ivar to Object is a whole-bootstrap change, not a local edit. Ivars are allocated
  # in mention order, and Object's land in the lowest slots of EVERY object -- including Class
  # objects, whose metadata sits at fixed slots that low-level code reads by hardcoded index
  # (see lib/core/class.rb). A new Object ivar shifts all of those. To add one:
  #   1. Mention it here before any other Object ivar, so it takes slot 1 (after @__class__).
  #   2. Bump ClassScope::CLASS_IVAR_NUM by one and shift EVERY hardcoded class-metadata index
  #      up by one (instance_size/name/superclass/subclasses/next_sibling in class.rb, and the
  #      `(index self N)` fixup below).
  #   3. Override its accessors on the type-tagged immediates (Integer/Symbol/nil/true/false),
  #      which have no storage at all and cannot hold or read the slot.
  #
  # At this point we have a "fixup to make as part of bootstrapping:
  #
  #  Class was created *before* Object existed, which means it is not linked into the
  #  subclasses array. As a result, unless we do this, Class will not inherit methods
  #  that are subsquently added to Object below. This *must* be the first thing to happen
  #  in Object, before defining any methods etc:
  #
  %s(assign (index self 4) Class)

  include Kernel

  def initialize
    # Default. Empty on purpose
  end

  def class
    @__class__
  end

  def object_id
    %s(__int self)
  end

  def hash
    object_id
  end

  def eql? other
    self.==(other)
  end

  def === other
    self.==(other)
  end

  def equal?(other)
    object_id == other.object_id
  end

  def inspect
    %s(assign buf (__alloc_leaf 20))
    %s(snprintf buf 20 "%p" self)
    %s(assign buf (__get_string buf))
    "#<#{self.class.name}:#{buf}>"
  end

  def to_s
    inspect
  end

  # Coerce a calling-side splat operand to an Array. `f(*x)`/`obj.send(*sym)` for a non-Array x reads x's
  # @len/buffer as garbage -> SIGSEGV; Ruby splats a non-Array (no #to_a) to [x]. Called via the
  # rewrite_splat_to_array transform, which evaluates this ONCE into a temp BEFORE the splat stack setup.
  def __splat_to_a
    return self if is_a?(Array)
    [self]
  end

  def to_enum(meth = :each, *args)
    GenericEnumerator.new(self, meth, *args)
  end
  def enum_for(meth = :each, *args)
    GenericEnumerator.new(self, meth, *args)
  end

  def == other
    object_id == other.object_id
  end

  def !
    false
  end

  def != other
    !(self == other)
  end

  def nil?
    false
  end

  # FIXME: per-class hack. The proper fix is a frozen bit in the slot-1 flags word so freeze
  # works uniformly for every object -- see the "Adding an ivar to Object" documentation at the
  # top of this file (that change is implemented but stashed, pending a parser regression).
  # Until then Object#freeze is a no-op and classes needing real frozen state (e.g. Array) use
  # a local @frozen ivar.
  def freeze
    self
  end

  def frozen?
    false
  end

  def method_missing (sym, *args)
    receiver_info = self.inspect
    raise "undefined method '#{sym.to_s}' for #{receiver_info}"
  end

    def respond_to?(method)
    # The vtable thunks make up a contiguous sequence of memory,
    # bounded by __vtable_thunks_start and __vtable_thunks_end
    m = Class.method_to_voff

    voff = m[method]
    return false if !voff # FIXME: Handle dynamically added.

    c = self.class
    %s(assign raw (callm voff __get_raw))
    %s(assign ptr (index c raw))
    %s(if (lt ptr __vtable_thunks_start) (return true))
    %s(if (gt ptr __vtable_thunks_end) (return true))
    return false
  end

  # Relying on s-exps here to prevent bootstrap issues
  # w/Fixnum#== / Fixnum#!= which again is relied on by
  # the basic Object#object_id. Perhaps replace those
  # instead
  #
  # FIXME: This will not handle eigenclasses correctly.
  def is_a?(c)
    %s(assign k (callm self class))
    %s(while (and (ne k c) (ne k Object)) (do
      (assign k (callm k superclass))
     ))

    %s(if (eq k c) (return true) (return false))
  end

  # FIXME: A proper alias would be more efficient,
  # but not yet supported
  def kind_of?(c)
    is_a?(c)
  end

  # instance_of? is an EXACT class match (unlike is_a?, which walks the ancestry).
  def instance_of?(c)
    self.class == c
  end

  def itself
    self
  end

  # The methods callable on this object (its class's instance methods). `all` (default true) mirrors
  # Ruby's methods(all=true); singleton methods are not tracked yet, so the false case is approximate.
  def methods(all = true)
    self.class.instance_methods(all)
  end

  # Kernel#tap: yield self to the block, then return self (for method chaining).
  def tap
    yield self
    self
  end

  # NOTE: Kernel#yield_self / #then intentionally omitted -- they must return an Enumerator when
  # called with no block, and the no-block path currently raises LocalJumpError which segfaults
  # (unhandled-raise limitation), regressing yield_self_spec from FAIL to CRASH. Re-add once the
  # Enumerator-without-block path works. See [[no-block-null-deref-crashes]].

  def display
    print self
    nil
  end

  # FIXME: Private
  def send sym, *args, &block
    __send__(sym, *args, &block)
  end

  # Forward a block so `obj.send(:each, &blk)` / to_enum work (the block becomes the callee's __closure__
  # via the 4th element of the callm s-expr in __send_for_obj__).
  def __send__ sym, *args, &block
    self.class.__send_for_obj__(self, sym, block, *args)
  end

  # FIXME: Add splat support for s-expressions / call so that
# the below works
#  def printf format, *args
#    %s(printf format (rest args))
#  end

  def p ob
    puts ob.inspect
    ob
  end

  def print *str
    na = str.length
    
    if na == 0
      %s(printf "nil")
      return
    end

    i = 0
    while i < na
      raw = str[i].to_s.__get_raw
      if raw
        %s(printf "%s" raw)
      end
      i = i + 1
    end
  end

  # Shallow copy: allocate a fresh instance of the same class and copy every ivar slot, then run
  # #initialize_copy (so subclasses can customise). The old `self.class.new` was wrong -- it re-ran
  # #initialize (with no args) and copied no ivars. Objects are @instance_size-slot arrays (slot 0 =
  # class, slots 1.. = ivars, per Class#allocate). String/Array/Hash override #dup, so this covers
  # Exception and plain objects.
  def dup
    copy = nil
    klass = self.class
    # sz (@instance_size) and the loop counter are RAW machine ints, so keep them in an s-expr `let`
    # scope -- a Ruby local would be a tagged Integer and (lt i sz)/(index copy i) would misbehave.
    %s(let (sz i)
        (assign sz (index klass 1))
        (assign copy (__array sz))
        (assign (index copy 0) klass)
        (assign i 1)
        (while (lt i sz) (do
          (assign (index copy i) (index self i))
          (assign i (add i 1)))))
    copy.initialize_copy(self)
    copy
  end

  # clone: like #dup but in full Ruby also copies frozen state and the singleton class. We do the same
  # shallow slot (ivar) copy as #dup; the freeze: keyword is accepted and ignored.
  def clone(*args)
    copy = nil
    klass = self.class
    %s(let (sz i)
        (assign sz (index klass 1))
        (assign copy (__array sz))
        (assign (index copy 0) klass)
        (assign i 1)
        (while (lt i sz) (do
          (assign (index copy i) (index self i))
          (assign i (add i 1)))))
    copy.initialize_copy(self)
    copy
  end

  # Default #initialize_copy: the ivars were already copied by #dup/#clone, so there is nothing more
  # to do. Subclasses override this to deep-copy or record, calling super for the default.
  def initialize_copy(other)
    self
  end

  # extend(*mods): full Ruby adds each module's instance methods to this object's singleton class.
  # Runtime singleton-method injection is not modelled, so this is a no-op that returns self (methods
  # from the module won't actually be added) -- but it stops the crash on objects that lacked #extend
  # (only Class had it). Kept on Object so every instance responds to it.
  def extend(*mods)
    self
  end

  # FIXME: Stub - should check if constant is actually defined
  # This minimal stub returns true to prevent segfaults
  def const_defined?(name)
    true
  end

  # FIXME: eval cannot be implemented in AOT compiler
  # Specs using eval will skip/fail but won't crash
  def eval(code, *args)
    STDERR.puts("eval not supported in AOT compiler")
    nil
  end

  # Stub for test framework - returns nil
  # WORKAROUND: No exceptions - validate args manually to avoid FPE crashes in specs
  def index(*args)
    if args.length != 1
      STDERR.puts("ArgumentError: wrong number of arguments (given #{args.length}, expected 1)")
      return nil
    end
    nil
  end

  # singleton_class - Get object's singleton class
  # Stub: Returns the regular class (not correct but prevents crashes)
  # Full implementation would require singleton class support
  def singleton_class
    self.class
  end
end

# BasicObject defined after Object to avoid circular dependency
# Parser defaults superclass to Object, so this makes BasicObject inherit from Object
# This is backwards from standard Ruby but avoids bootstrap complexity
class BasicObject
  def initialize
  end
end
