# Ruby 3.2 Data: immutable value objects. `Data.define(:a, :b)` returns a class whose instances expose
# readers a/b (served via method_missing from an internal hash), plus members/to_h/with/deconstruct/==.
# Members are held in a registry keyed by the class's object_id -- an anonymous class (Class.new) has no
# name, so a name-based __classivar__ store is not available.
class Data
  def self.__data_registry
    @@__data_registry ||= {}
    @@__data_registry
  end

  def self.define(*members, &block)
    syms = []
    i = 0
    while i < members.length
      syms << members[i].to_sym
      i = i + 1
    end
    klass = Class.new(Data)
    Data.__data_registry[klass.object_id] = syms
    klass.class_eval(&block) if block
    klass
  end

  # Look up a class's members, walking the superclass chain so a subclass of a Data class (or an anonymous
  # Class.new(SomeData)) inherits its members.
  def self.__members_for(klass)
    k = klass
    while k
      m = Data.__data_registry[k.object_id]
      return m if m
      k = k.superclass
    end
    []
  end

  def self.members
    Data.__members_for(self)
  end

  def self.[](*args, **kwargs)
    new(*args, **kwargs)
  end

  def initialize(*args, **kwargs)
    members = Data.__members_for(self.class)
    h = {}
    if kwargs.length > 0
      i = 0
      while i < members.length
        h[members[i]] = kwargs[members[i]]
        i = i + 1
      end
    else
      i = 0
      while i < args.length
        h[members[i]] = args[i]
        i = i + 1
      end
    end
    @__data = h
  end

  def members
    Data.__members_for(self.class)
  end

  def method_missing(name, *args)
    if @__data && @__data.has_key?(name)
      @__data[name]
    else
      super
    end
  end

  def respond_to_missing?(name, include_private = false)
    @__data && @__data.has_key?(name)
  end

  def to_h
    @__data.dup
  end

  def deconstruct
    m = members
    r = []
    i = 0
    while i < m.length
      r << @__data[m[i]]
      i = i + 1
    end
    r
  end

  def deconstruct_keys(keys)
    @__data.dup
  end

  def with(**changes)
    merged = @__data.dup
    changes.each do |k, v|
      merged[k] = v
    end
    n = self.class.allocate
    n.__data_set(merged)
    n
  end

  def __data_set(h)
    @__data = h
  end

  def ==(other)
    return false if other.class != self.class
    other.to_h == @__data
  end

  def eql?(other)
    self == other
  end

  def hash
    @__data.hash
  end

  def inspect
    m = members
    parts = []
    i = 0
    while i < m.length
      name = m[i].to_s
      val = @__data[m[i]].inspect
      parts << (name + "=" + val)
      i = i + 1
    end
    "#<data " + parts.join(", ") + ">"
  end

  def to_s
    inspect
  end
end
