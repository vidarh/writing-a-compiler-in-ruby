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

  # Identity hash. NOT plain object_id: that tags the RAW POINTER as a fixnum, and a heap address at
  # or above 2^30 overflows the 30-bit tagged range -- Hash#_find_slot's `h % @capacity` then computes
  # a position beyond the table and the probe loop walks out-of-bounds memory that never looks empty:
  # an INFINITE LOOP that appears/disappears with allocation layout (whether this object's address
  # crosses 2^30). Shift the pointer down 3 bits (allocations are 8-aligned, so no distribution is
  # lost) and mask to 29 bits so the result always fits a non-negative fixnum. sarl is an ARITHMETIC
  # shift and stack/high addresses have the sign bit set, hence the mask.
  def hash
    %s(__int (bitand (sarl 3 self) 536870911))
  end

  def eql? other
    self.==(other)
  end

  def === other
    self.==(other)
  end

  # Identity: a RAW pointer compare. NOT object_id equality -- object_id tags the raw pointer as a
  # fixnum, and for heap addresses at or above 2^30 the tag overflows into (broken) heap-integer
  # territory, where == mis-compares: the SAME object then reads as not-equal?, purely depending on
  # where the allocator placed it. (That layout-sensitivity broke the define_method registry's
  # identity scans, among other things.)
  def equal?(other)
    %s(if (eq self other) (return true))
    false
  end

  # Truthiness predicate used by FalseClass#|/#^ and TrueClass#&/#^ (e.g. `false | other` is
  # `other.__true?`). Every object except nil and false is truthy, so the default is true here;
  # NilClass and FalseClass override it to be falsy. Without this, `false | true` (and any
  # `false | <object>`) raised "undefined method '__true?'".
  def __true?
    true
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
    # Ruby's splat coercion: nil splats to [] (never [nil]); an object that responds to #to_a is expanded
    # via it (so `*hash`, `*range`, and a mock with a stubbed #to_a expand correctly); everything else
    # wraps to [self]. Previously this always wrapped to [self], which both mis-expanded such objects and
    # -- crucially for the array-literal splat path -- meant `*nil` had to be left uncoerced.
    return [] if nil?
    if respond_to?(:to_a)
      r = to_a
      # Only use to_a's result when it is actually an Array; otherwise the splat machinery would read
      # @len off a non-Array and crash. (MRI raises TypeError here; wrapping to [self] is the safe fallback.)
      return r if r.is_a?(Array)
    end
    [self]
  end

  def to_enum(meth = :each, *args)
    GenericEnumerator.new(self, meth, *args)
  end
  def enum_for(meth = :each, *args)
    GenericEnumerator.new(self, meth, *args)
  end

  # Ivar-by-name reflection stubs. Ivar slots are assigned STATICALLY by the compiler with no
  # runtime name->slot table, so set is a lossy no-op (returns the value) and get reports nil.
  # Wrong for real reflection, but fixtures calling these at load (marshal's set ivars on
  # literals) aborted whole spec files on the missing methods.
  def instance_variable_set(name, value)
    value
  end

  def instance_variable_get(name)
    nil
  end

  def instance_variables
    []
  end

  def instance_variable_defined?(name)
    false
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

  # Every missing-method vtable thunk lands HERE (see __vtable_thunks_helper in compiler.rb), not
  # directly in method_missing: methods installed at RUNTIME via Class#define_method live in the
  # $__defined_methods registry (a vtable slot holds a raw function pointer, not a Proc), so consult
  # the registry along the receiver's class chain first, then fall back to method_missing (which a
  # user class may override). The call-site block arrives as &blk and is forwarded.
  def __dispatch_missing__(sym, *args, &blk)
    if $__dm_classes
      pr = self.class.__find_defined_method(sym)
      if pr
        # Invoke the registered proc with self rebound; the call-site block travels as
        # __call_with_self's explicit blkarg (it cannot take &blk -- see the note there).
        return pr.__call_with_self(self, blk, *args)
      end
    end
    method_missing(sym, *args, &blk)
  end

  def method_missing (sym, *args)
    receiver_info = self.inspect
    # Throw through the exception runtime DIRECTLY, not via `raise`: raise is an ordinary
    # method dispatched on self, so an object that OVERRIDES raise (thread/kernel raise_spec
    # fixtures do) re-enters its override from here -- and when that override was itself the
    # missing-method trampoline's caller, the two recurse until stack overflow (SIGSEGV deep
    # inside calloc). NoMethodError with name/receiver/args populated (MRI class; was
    # RuntimeError, which failed every `should raise_error(NoMethodError)` expectation).
    e = NoMethodError.new("undefined method '#{sym.to_s}' for #{receiver_info}")
    e.__set_name_receiver(sym, self)
    e.__set_args(args)
    $__exception_runtime.raise(e)
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

  # Kernel#then / #yield_self: yield self to the block and return the block's result; with no block,
  # return a size-1 Enumerator yielding self (via to_enum, which now works -- the previous LocalJumpError
  # segfault this method was omitted for is avoided by the to_enum guard).
  def then
    return to_enum(:then) if !block_given?
    yield self
  end
  alias yield_self then

  def display
    print self
    nil
  end

  # FIXME: Private
  def send sym, *args, &block
    __send__(sym, *args, &block)
  end

  # public_send is like send but only invokes public methods. We do not track method visibility, so it
  # behaves as send here (private/protected methods are still callable). Enough to stop the "undefined
  # method 'public_send'" crash and pass the specs that just exercise dispatch.
  def public_send sym, *args, &block
    __send__(sym, *args, &block)
  end

  # Forward a block so `obj.send(:each, &blk)` / to_enum work (the block becomes the callee's __closure__
  # via the 4th element of the callm s-expr in __send_for_obj__).
  def __send__ sym, *args, &block
    self.class.__send_for_obj__(self, sym, block, *args)
  end

  # Kernel#open: delegate to File.open, or IO.popen for a "|cmd" path.
  def open(path, *args, &block)
    if !path.is_a?(String) && path.respond_to?(:to_str)
      path = path.to_str
    end
    if path.is_a?(String) && path.length > 0 && path[0] == 124   # '|'
      return IO.popen(path[1, path.length - 1], *args, &block)
    end
    File.open(path, *args, &block)
  end

  def p ob
    puts ob.inspect
    ob
  end

  # Coerce a format argument to an Integer the way Ruby's integer conversions do: an Integer is used
  # directly, otherwise #to_int is preferred (Integer() semantics) and #to_i is the fallback. This lets
  # objects that expose only #to_int (a common mspec mock idiom) format under %d/%x/%o/%b.
  def __fmt_to_int(val)
    return val if val.is_a?(Integer)
    if val.is_a?(String)
      # MRI coerces %d/%x/... string arguments STRICTLY (like Kernel#Integer).
      r = val.__parse_int(0, true)
      raise ArgumentError, "invalid value for Integer(): #{val.inspect}" if r.nil?
      return r
    end
    return val.to_int if val.respond_to?(:to_int)
    return val.to_i if val.respond_to?(:to_i)
    raise TypeError, "can't convert #{val.class} into Integer"
  end

  # Minimal sprintf: parses %[flags][width][.prec]type. Types: d/i/u, s, x/X, o, b, c, f/e/g, p, %.
  # Flags: - (left), 0 (zero-pad), + / space (sign). char-code comparisons (no regex; self-host safe).
  def __sprintf(fmt, args)
    out = ""
    ai = 0
    i = 0
    flen = fmt.length
    while i < flen
      c = fmt[i]
      if c != 37   # not '%'
        out = out + c.chr
        i = i + 1
      else
        i = i + 1
        left = false
        zero = false
        plus = false
        space = false
        cont = true
        while cont && i < flen
          fc = fmt[i]
          if fc == 45
            left = true; i = i + 1
          elsif fc == 48
            zero = true; i = i + 1
          elsif fc == 43
            plus = true; i = i + 1
          elsif fc == 32
            space = true; i = i + 1
          else
            cont = false
          end
        end
        width = 0
        while i < flen && fmt[i] >= 48 && fmt[i] <= 57
          width = width * 10 + (fmt[i] - 48)
          i = i + 1
        end
        prec = -1
        if i < flen && fmt[i] == 46
          i = i + 1
          prec = 0
          while i < flen && fmt[i] >= 48 && fmt[i] <= 57
            prec = prec * 10 + (fmt[i] - 48)
            i = i + 1
          end
        end
        if i >= flen
          raise ArgumentError, "incomplete format specifier; use %% (double %) instead"
        end
        type = fmt[i]
        i = i + 1
        # Named references: %{name} interpolates hash[name] as a string;
        # %<name>TYPE reads the value then formats with TYPE. args[0] must be
        # a Hash; a missing key raises KeyError (kernel/sprintf specs).
        named = nil
        if type == 123 || type == 60          # '{' / '<'
          closer = 125                         # '}'
          closer = 62 if type == 60            # '>'
          nm = ""
          while i < flen && fmt[i] != closer
            nm = nm + fmt[i].chr
            i = i + 1
          end
          raise ArgumentError, "malformed format string" if i >= flen
          i = i + 1
          h = args[0]
          raise ArgumentError, "one hash required" if !h.is_a?(Hash)
          k = nm.to_sym
          raise KeyError, "key<#{nm}> not found" if !h.key?(k)
          if type == 123
            out = out + h[k].to_s
            next
          end
          named = h[k]
          type = fmt[i]
          i = i + 1
        end
        if type == 37
          out = out + "%"
        else
          if named.nil?
            raise ArgumentError, "too few arguments" if ai >= args.length
            val = args[ai]
            ai = ai + 1
          else
            val = named
          end
          body = ""
          numeric = false
          neg = false
          if type == 100 || type == 105 || type == 117   # d i u
            n = __fmt_to_int(val)
            numeric = true
            if n < 0
              neg = true
              body = (0 - n).to_s
            else
              body = n.to_s
            end
          elsif type == 115   # s
            body = val.to_s
            body = body.slice(0, prec) if prec >= 0
          elsif type == 120   # x
            body = __fmt_to_int(val).to_s(16); numeric = true
          elsif type == 88    # X
            body = __fmt_to_int(val).to_s(16).upcase; numeric = true
          elsif type == 111   # o
            body = __fmt_to_int(val).to_s(8); numeric = true
          elsif type == 98    # b
            body = __fmt_to_int(val).to_s(2); numeric = true
          elsif type == 99    # c
            if val.is_a?(Integer)
              body = val.chr
            else
              # MRI takes the FIRST character of a longer string.
              s = val.to_s
              raise ArgumentError, "%c requires a character" if s.length == 0
              body = s[0, 1].to_s
            end
          elsif type == 102 || type == 101 || type == 103 || type == 69 || type == 71   # f e g E G
            body = __format_float(val.to_f, prec < 0 ? 6 : prec)
            numeric = true
            if body.length > 0 && body[0] == 45
              neg = true
              body = body.slice(1, body.length - 1)
            end
          elsif type == 112   # p
            body = val.inspect
          elsif type == 97 || type == 65      # a A (hex float) -- Float-blocked, format decimally
            body = val.to_s
          else
            raise ArgumentError, "malformed format string - %#{type.chr}"
          end
          sign = ""
          if numeric
            if neg
              sign = "-"
            elsif plus
              sign = "+"
            elsif space
              sign = " "
            end
          end
          total = sign.length + body.length
          if width > total
            pad = width - total
            if left
              out = out + sign + body + (" " * pad)
            elsif zero && numeric && prec < 0
              out = out + sign + ("0" * pad) + body
            else
              out = out + (" " * pad) + sign + body
            end
          else
            out = out + sign + body
          end
        end
      end
    end
    out
  end

  # Format a Float with `decimals` places (rounded). Approximate but adequate for %f in the common cases.
  def __format_float(f, decimals)
    neg = f < 0
    f = f * -1 if neg
    mult = 1
    d = 0
    while d < decimals
      mult = mult * 10
      d = d + 1
    end
    intpart = (f * mult).to_i
    whole = intpart / mult
    frac = intpart - (whole * mult)
    result = whole.to_s
    if decimals > 0
      fracstr = frac.to_s
      while fracstr.length < decimals
        fracstr = "0" + fracstr
      end
      result = result + "." + fracstr
    end
    result = "-" + result if neg
    result
  end

  def sprintf(fmt, *args)
    __sprintf(fmt.to_s, args)
  end

  def format(fmt, *args)
    __sprintf(fmt.to_s, args)
  end

  def printf(fmt, *args)
    s = __sprintf(fmt.to_s, args)
    %s(printf "%s" (callm s __get_raw))
    nil
  end

  def warn(*msgs)
    msgs.each do |m|
      $stderr.write(m.to_s + "\n")
    end
    nil
  end

  def putc(ch)
    if ch.is_a?(Integer)
      %s(printf "%c" (callm ch __get_raw))
    else
      b = ch.to_s[0]
      if b
        %s(printf "%c" (callm b __get_raw))
      end
    end
    ch
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

  # clone: like #dup here (we do not model frozen state or the singleton class). Delegate to the proven
  # #dup path (a tagged fixnum returns self via the guard below; heap objects get a shallow slot copy).
  def clone(*args)
    %s(if (ne (bitand self 1) 0) (return self))
    dup
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

  # Method-visibility declarations. At the top level `self` is the main Object, where `public :foo` /
  # `private :foo` / `protected :foo` are legal (they set visibility of Object's instance methods). We
  # do not model method visibility, so these are no-ops here -- but without them top-level visibility
  # calls (common in spec fixtures) raise "undefined method 'public' for #<Object>". Class/Module have
  # their own equivalents; this only covers plain objects such as main.
  def public(*args)
    nil
  end
  def private(*args)
    nil
  end
  def protected(*args)
    nil
  end

  # FIXME: Stub - should check if constant is actually defined
  # This minimal stub returns true to prevent segfaults
  def const_defined?(name)
    true
  end

  # Support `case x; when *recv` -- true if any element of the splatted receiver === target.
  # The splat operand is array-like (Ruby coerces via to_a); we handle Array directly, nil as empty,
  # and fall back to a single-element check. Uses a while loop (no block) so it is self-host safe.
  def __when_splat_match(target)
    if is_a?(Array)
      ary = self
    elsif self.nil?
      ary = []
    elsif respond_to?(:to_a)
      ary = to_a
    else
      ary = [self]
    end
    i = 0
    n = ary.length
    while i < n
      return true if ary[i] === target
      i = i + 1
    end
    false
  end

  # FIXME: eval cannot be implemented in AOT compiler
  # Specs using eval will skip/fail but won't crash
  def eval(code, *args)
    STDERR.puts("eval not supported in AOT compiler")
    nil
  end

  # Stub for test framework - returns nil
  def index(*args)
    if args.length != 1
      raise ArgumentError, "wrong number of arguments (given #{args.length}, expected 1)"
    end
    nil
  end

  # singleton_class - the object's own metaclass, created on demand: a fresh class whose superclass is the
  # object's current class, spliced in as the object's class (slot 0). Idempotent via a registry keyed by
  # object_id, so repeated calls (and multiple singleton `def`s) share one singleton. `self` is unchanged;
  # only where methods get installed differs.
  def singleton_class
    reg = Object.__singleton_registry
    oid = object_id
    existing = reg[oid]
    return existing if existing
    sc = nil
    %s(assign sc (__new_class_object __vtable_size (index self 0) __vtable_size (index (index self 0) 0)))
    %s(assign (index sc 2) "#<Class:singleton>")
    %s(assign (index self 0) sc)
    reg[oid] = sc
    sc
  end

  def self.__singleton_registry
    @@__singleton_registry ||= {}
    @@__singleton_registry
  end

  # The class object that a bare `def` in a context whose self is this object should install into. An
  # ordinary object installs a singleton method (on its singleton class); Module/Class override to return
  # self (a bare def there is an instance method). Used by compile_defm for defs inside blocks.
  def __def_target
    singleton_class
  end

  # Evaluate the block with self bound to this object (its `def`s become singleton methods on it, via
  # __def_target -> singleton_class). instance_exec additionally forwards arguments to the block.
  def instance_eval &block
    block.__call_with_self(self, nil) if block
  end

  def instance_exec *args, &block
    block.__call_with_self(self, nil, *args) if block
  end
end

# BasicObject defined after Object to avoid circular dependency
# Parser defaults superclass to Object, so this makes BasicObject inherit from Object
# This is backwards from standard Ruby but avoids bootstrap complexity
class BasicObject
  def initialize
  end
end
