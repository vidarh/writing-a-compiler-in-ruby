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

  # FIXME: Add splat support for s-expressions / call so that
# the below works
#  def printf format, *args
#    %s(printf format (rest args))
#  end

  def p ob
    puts ob.inspect
    ob
  end

  # Coerce a format argument to an Integer the way Ruby's integer conversions do: an Integer is used
  # directly, otherwise #to_int is preferred (Integer() semantics) and #to_i is the fallback. This lets
  # objects that expose only #to_int (a common mspec mock idiom) format under %d/%x/%o/%b.
  def __fmt_to_int(val)
    return val if val.is_a?(Integer)
    return val.to_int if val.respond_to?(:to_int)
    val.to_i
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
        type = fmt[i]
        i = i + 1
        if type == 37
          out = out + "%"
        else
          val = args[ai]
          ai = ai + 1
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
            body = val.is_a?(Integer) ? val.chr : val.to_s
          elsif type == 102 || type == 101 || type == 103   # f e g
            body = __format_float(val.to_f, prec < 0 ? 6 : prec)
            numeric = true
            if body.length > 0 && body[0] == 45
              neg = true
              body = body.slice(1, body.length - 1)
            end
          elsif type == 112   # p
            body = val.inspect
          else
            body = val.to_s
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

  # clone: like #dup but in full Ruby also copies frozen state and the singleton class. We do the same
  # shallow slot (ivar) copy as #dup; the freeze: keyword is accepted and ignored.
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
  # WORKAROUND: No exceptions - validate args manually to avoid FPE crashes in specs
  def index(*args)
    if args.length != 1
      STDERR.puts("ArgumentError: wrong number of arguments (given #{args.length}, expected 1)")
      return nil
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
    block.__call_with_self(self) if block
  end

  def instance_exec *args, &block
    block.__call_with_self(self, *args) if block
  end
end

# BasicObject defined after Object to avoid circular dependency
# Parser defaults superclass to Object, so this makes BasicObject inherit from Object
# This is backwards from standard Ruby but avoids bootstrap complexity
class BasicObject
  def initialize
  end
end
