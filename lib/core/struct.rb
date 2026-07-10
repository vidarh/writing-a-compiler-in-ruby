# Struct: `Struct.new(:a, :b)` returns a new *class* (subclass of Struct) whose instances expose
# accessors a/a= (served via method_missing from an internal values array), plus []/[]=, to_a, to_h,
# members, each, each_pair, ==, size, inspect, dig, values_at and friends.
#
# Members are held in registries keyed by the created class's object_id -- an anonymous class
# (Class.new) has no name, so a name-based class-ivar store is not available. This mirrors lib/core/
# data.rb. Class.new(Struct) subclasses inherit their members by walking the superclass chain.
#
# The single method `Struct.new` is overloaded: called ON Struct itself it builds a subclass; called on
# a Struct subclass it builds an instance (mirroring Class#new). That is how MRI models it too.
class Struct
  # Internal implementation ivars, hidden from reflection/Marshal per-class (see Object#__hidden_ivars).
  def __hidden_ivars
    super + [:@__struct_values, :@__struct_registry, :@__struct_kwinit, :@__comparing, :@__hashing, :@__inspecting]
  end


  def self.__struct_registry
    @@__struct_registry ||= {}
    @@__struct_registry
  end

  def self.__struct_kwinit
    @@__struct_kwinit ||= {}
    @@__struct_kwinit
  end

  def self.new(*args, **kwargs, &block)
    if self.equal?(Struct)
      # --- class-creation mode: Struct.new(:a, :b) or Struct.new("Name", :a, :b) ---
      start = 0
      # A leading String or nil occupies the (optional) name position. A String names the struct
      # (Struct::Name); nil means anonymous. We cannot register the constant here (no const_set yet), so we
      # skip the slot either way rather than treating it as a member (nil.to_sym would crash).
      if args.length > 0 && (args[0].is_a?(String) || args[0].nil?)
        start = 1
      end
      syms = []
      i = start
      while i < args.length
        a = args[i]
        # Only Symbols and Strings are valid member names. Anything else -- a Float, nil, an Array, or an
        # object that merely defines #to_sym -- is a TypeError in MRI. Match that instead of crashing on a
        # missing #to_sym (NoMethodError).
        if !a.is_a?(Symbol) && !a.is_a?(String)
          raise TypeError.new("#{a.inspect} is not a symbol nor a string")
        end
        sym = a.to_sym
        raise ArgumentError.new("duplicate member: #{sym}") if syms.include?(sym)
        syms << sym
        i = i + 1
      end
      klass = Class.new(Struct)
      # `Struct.new("Name", ...)` names the class Struct::Name. Register it in the runtime
      # constant table (see Kernel#__const_set_global) under the qualified key so a later
      # `Struct::Name` -- compiled as a runtime __const_get -- resolves. Previously the name
      # was silently dropped and marshal's fixtures aborted their whole file at load on
      # "uninitialized constant Useful".
      if start == 1 && args[0]
        full = "Struct::" + args[0]
        __const_set_global(full, klass)
        # Also set the class object's @name (metadata slot 2, a raw C string) so
        # klass.name / #inspect report "Struct::Animal" rather than the inherited
        # "Struct". slot 2 = @name (see the layout comment in lib/core/class.rb).
        %s(assign (index klass 2) (callm full __get_raw))
      end
      Struct.__struct_registry[klass.object_id] = syms
      # Store the raw keyword_init: value (or nil when unspecified) so keyword_init? can distinguish
      # true / false / nil, while initialize still just tests it for truthiness.
      Struct.__struct_kwinit[klass.object_id] = kwargs.has_key?(:keyword_init) ? kwargs[:keyword_init] : nil
      klass.class_eval(&block) if block
      klass
    else
      # --- instance-creation mode: mirror Class#new (allocate + initialize dispatch) ---
      ob = allocate
      ob.initialize(*args, &block)
      ob
    end
  end

  # Members for a class, walking the superclass chain so subclasses (and Class.new(SomeStruct)) inherit.
  # A `class X < Struct` subclass (created without Struct.new) has no registry entry, so the walk can run
  # all the way to Object -- whose #superclass returns Object itself in this runtime (bootstrap). Stop when
  # the superclass no longer changes so that walk terminates.
  def self.__members_for(klass)
    k = klass
    while k
      m = Struct.__struct_registry[k.object_id]
      return m if m
      sup = k.superclass
      break if sup.equal?(k)
      k = sup
    end
    []
  end

  def self.__kwinit_for(klass)
    k = klass
    while k
      r = Struct.__struct_registry[k.object_id]
      return Struct.__struct_kwinit[k.object_id] if r
      sup = k.superclass
      break if sup.equal?(k)
      k = sup
    end
    false
  end

  def self.members
    Struct.__members_for(self)
  end

  # true if the struct was created with a truthy keyword_init:, false if created with keyword_init: false,
  # and nil if keyword_init: was not given (or given as nil) -- matching MRI's tri-state result.
  def self.keyword_init?
    v = Struct.__kwinit_for(self)
    return nil if v.nil?
    v ? true : false
  end

  def self.[](*args, **kwargs)
    new(*args, **kwargs)
  end

  def initialize(*args, **kwargs)
    members = Struct.__members_for(self.class)
    vals = []
    use_kw = Struct.__kwinit_for(self.class) || (args.length == 0 && kwargs.length > 0)
    if use_kw
      i = 0
      while i < members.length
        vals << kwargs[members[i]]
        i = i + 1
      end
    else
      if args.length > members.length
        raise ArgumentError.new("struct size differs")
      end
      i = 0
      while i < members.length
        vals << (i < args.length ? args[i] : nil)
        i = i + 1
      end
    end
    @__struct_values = vals
  end

  def __struct_values
    @__struct_values
  end

  # A subclass initializer may set a member (via the a= writer) BEFORE calling super, e.g.
  #   def initialize(*a); self.make = "Honda"; super(*a); end
  # at which point @__struct_values has not been created yet. Lazily allocate a nil-filled array so such
  # a write does not dereference nil. super's own initialize then overwrites it with the real values.
  def __ensure_values
    if @__struct_values.nil?
      m = Struct.__members_for(self.class)
      vals = []
      i = 0
      while i < m.length
        vals << nil
        i = i + 1
      end
      @__struct_values = vals
    end
    @__struct_values
  end

  def __member_index(sym)
    members = Struct.__members_for(self.class)
    i = 0
    while i < members.length
      return i if members[i] == sym
      i = i + 1
    end
    -1
  end

  # Readers (`s.a`) and writers (`s.a = v`) are served here rather than as generated methods.
  def method_missing(name, *args)
    s = name.to_s
    if s.end_with?("=")
      base = s[0...(s.length - 1)].to_sym
      idx = __member_index(base)
      if idx >= 0
        __ensure_values[idx] = args[0]
        return args[0]
      end
    else
      idx = __member_index(name)
      if idx >= 0
        return __ensure_values[idx]   # tolerate a read before initialize (super) has populated the array
      end
    end
    super
  end

  def respond_to_missing?(name, include_private = false)
    s = name.to_s
    s = s[0...(s.length - 1)] if s.end_with?("=")
    __member_index(s.to_sym) >= 0
  end

  def members
    Struct.__members_for(self.class)
  end

  def [](key)
    if key.is_a?(Integer)
      n = @__struct_values.length
      i = key < 0 ? n + key : key
      raise IndexError.new("offset #{key} too large for struct(size:#{n})") if i >= n
      raise IndexError.new("offset #{key} too small for struct(size:#{n})") if i < 0
      @__struct_values[i]
    else
      idx = __member_index(key.to_sym)
      raise NameError.new("no member '#{key}' in struct") if idx < 0
      @__struct_values[idx]
    end
  end

  def []=(key, value)
    if key.is_a?(Integer)
      i = key
      i = @__struct_values.length + i if i < 0
      @__struct_values[i] = value
    else
      idx = __member_index(key.to_sym)
      raise NameError.new("no member '#{key}' in struct") if idx < 0
      @__struct_values[idx] = value
    end
  end

  def to_a
    @__struct_values.dup
  end
  alias values to_a
  alias deconstruct to_a

  def to_h
    m = members
    h = {}
    i = 0
    while i < m.length
      h[m[i]] = @__struct_values[i]
      i = i + 1
    end
    h
  end

  # deconstruct_keys(keys) -- for pattern matching. nil returns the full hash; otherwise a hash of just the
  # requested keys that exist, preserving the caller's key objects. If more keys are requested than there
  # are members, or a requested key is absent, MRI returns what it has matched so far (and {} for the
  # too-many-keys case, since a full match is then impossible). The argument is REQUIRED (0 args raises).
  def deconstruct_keys(keys)
    return to_h if keys.nil?
    m = members
    r = {}
    return r if keys.length > m.length
    i = 0
    while i < keys.length
      k = keys[i]
      sym = k.is_a?(String) ? k.to_sym : k
      idx = __member_index(sym)
      break if idx < 0
      r[k] = @__struct_values[idx]
      i = i + 1
    end
    r
  end

  def each(&block)
    return to_enum(:each) unless block
    @__struct_values.each(&block)
    self
  end

  def each_pair(&block)
    return to_enum(:each_pair) unless block
    m = members
    i = 0
    while i < m.length
      block.call(m[i], @__struct_values[i])
      i = i + 1
    end
    self
  end

  def size
    @__struct_values.length
  end
  alias length size

  def values_at(*args)
    n = @__struct_values.length
    r = []
    args.each do |a|
      if a.is_a?(Range)
        # Range elements beyond the struct produce nil (no error), matching MRI.
        a.each do |j|
          idx = j < 0 ? n + j : j
          r << (idx >= 0 && idx < n ? @__struct_values[idx] : nil)
        end
      else
        idx = a < 0 ? n + a : a
        raise IndexError.new("offset #{a} too large for struct(size:#{n})") if idx >= n
        raise IndexError.new("offset #{a} too small for struct(size:#{n})") if idx < 0
        r << @__struct_values[idx]
      end
    end
    r
  end

  def select(&block)
    return to_enum(:select) unless block
    r = []
    @__struct_values.each do |v|
      r << v if block.call(v)
    end
    r
  end
  alias filter select

  def dig(key, *rest)
    v = nil
    if key.is_a?(Integer)
      v = @__struct_values[key]
    else
      idx = __member_index(key.to_sym)
      v = idx >= 0 ? @__struct_values[idx] : nil
    end
    return v if rest.empty? || v.nil?
    v.dig(*rest)
  end

  def ==(other)
    return true if other.equal?(self)
    return false if other.class != self.class
    # Recursion guard for self-referential structs (x[:a] = x): while we are already comparing this
    # object, treat a re-entry as equal so a genuine difference elsewhere still makes the whole compare
    # false, but an infinite structure does not overflow the stack. Single-threaded, so a plain flag is
    # sufficient. Mirrors MRI's recursion handling.
    return true if @__comparing
    @__comparing = true
    result = (other.to_a == @__struct_values)
    @__comparing = false
    result
  end

  def eql?(other)
    # Like ==, but corresponding elements must be #eql? (stricter): a Struct with a 1 is NOT eql?
    # to one with 1.0, though they are ==. Delegates the element-wise eql? to Array#eql?.
    return true if other.equal?(self)
    return false if other.class != self.class
    return true if @__comparing
    @__comparing = true
    result = other.to_a.eql?(@__struct_values)
    @__comparing = false
    result
  end

  def hash
    # Recursion guard, as for ==: a self-referential struct (x[:a] = x) would otherwise recurse forever
    # through Array#hash. Returning a constant on re-entry keeps the hash finite and consistent.
    return 0 if @__hashing
    @__hashing = true
    h = @__struct_values.hash
    @__hashing = false
    h
  end

  def inspect
    # Cycle guard: a self-referential struct (a member pointing back at the struct) would otherwise recurse
    # through inspect forever -> stack overflow / segfault. Mirror Array#/Data#inspect's @__inspecting flag.
    if @__inspecting
      return "#<struct ...>"
    end
    @__inspecting = true
    m = members
    parts = []
    i = 0
    while i < m.length
      parts << (m[i].to_s + "=" + @__struct_values[i].inspect)
      i = i + 1
    end
    @__inspecting = false
    "#<struct " + parts.join(", ") + ">"
  end
  alias to_s inspect
end
