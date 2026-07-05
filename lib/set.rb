# FIXME: Doesn't belong here, but for some reason
# including it in lib/core/array.rb causes problems..
class Array
  def -(other_array)
    self.reject do |item| 
      other_array.include?(item)
    end
  end
end

#
# FIXME
# This is an awful, quick and dirty stub of a Set implementation
# to get some of the basics in place
#
class Set
  # Set is Enumerable: this provides map/select/reject/inject/min/max/sort/count/include?/... for free
  # via #each, instead of stubbing each one. (Set defines its own #each, #select, #include? where it
  # needs set-specific behaviour; those override the Enumerable versions.)
  include Enumerable

  def initialize(enum = nil)
    @set = Hash.new # Told you it was dirty
    if enum
      enum.each { |e| self << e }
    end
  end

  def size
    @set.size
  end

  # Set#select is NOT overridden in MRI (<= 3.2): Enumerable#select semantics,
  # returning an Array. Direct @set iteration just avoids the extra to_a.
  def select(&block)
    a = []
    @set.each do |e,_|
      if block.call(e)
        a << e
      end
    end
    a
  end

  def filter(&block)
    select(&block)
  end

  def each
    @set.each do |k,_|
      yield(k)
    end
  end

  def << k
    @set[k]=1
    self
  end
  alias add <<

  # Add k unless already present; return self if added, nil if it was already there.
  def add? k
    return nil if @set[k] == 1
    @set[k] = 1
    self
  end

  def empty?
    @set.size == 0
  end

  def length
    @set.size
  end

  def clear
    @set = Hash.new
    self
  end

  # Add every element of other to self (mutating); returns self.
  def merge other
    other.each {|e| @set[e] = 1 }
    self
  end

  def ==(other)
    return true if equal?(other)
    return false if !other.is_a?(Set)
    return false if size != other.size
    @set.each {|k,_| return false if !other.include?(k) }
    true
  end

  def | other
    s = dup
    other.each {|e| s << e }
    s
  end
  alias union |

  def & other
    s = Set.new
    each {|e| s << e if other.include?(e) }
    s
  end
  alias intersection &

  def subset? other
    return false if size > other.size
    r = true
    each {|e| r = false if !other.include?(e) }
    r
  end
  alias <= subset?

  def superset? other
    other.subset?(self)
  end
  alias >= superset?

  def proper_subset? other
    size < other.size && subset?(other)
  end
  alias < proper_subset?

  def proper_superset? other
    size > other.size && superset?(other)
  end
  alias > proper_superset?

  def intersect? other
    r = false
    each {|e| r = true if other.include?(e) }
    r
  end

  def disjoint? other
    !intersect?(other)
  end

  def replace other
    @set = Hash.new
    other.each {|e| @set[e] = 1 }
    self
  end

  # Delete o if present, returning self; nil if it was not a member.
  def delete? o
    return nil if @set[o] != 1
    @set.delete(o)
    self
  end

  def to_a
    @set.keys
  end

  def inspect
    # Cycle guard: a self-referential set (s << s) would recurse forever through k.inspect -> segfault.
    if @__inspecting
      return "#<Set: {...}>"
    end
    @__inspecting = true
    out = "#<Set: {"
    first = true
    @set.each do |k,_|
      if first
        first = false
      else
        out << ", "
      end
      out << k.inspect
    end
    out << "}>"
    @__inspecting = false
    out
  end

  alias to_s inspect

  def member?(m)
    @set[m] == 1
  end

  # FIXME: alias
  def include?(m)
    member?(m)
  end

  def self.[] *args
    s = Set.new
    args.each do |a|
      s << a
    end
    s
  end

  def dup
    s = Set.new
    @set.each do |k,_|
      s << k.dup
    end
    s
  end

  def + other
    s = dup
    other.each do |e|
      s << e
    end
    s
  end

  def - other
    Set.new + select {|item| !other.include?(item) }
  end

  def delete key
    @set.delete(key)
    self
  end

  # Remove every element of enum from self; returns self.
  def subtract(enum)
    enum.each { |e| @set.delete(e) }
    self
  end

  # Set difference/union/intersection/xor operators over enumerables.
  def ^(enum)
    other = Set.new(enum)
    result = Set.new
    each { |e| result << e if !other.include?(e) }
    other.each { |e| result << e if !include?(e) }
    result
  end

  def union(*enums)
    r = dup
    enums.each { |e| r = r | e }
    r
  end

  def intersection(*enums)
    r = self
    enums.each { |e| r = r & e }
    r
  end

  def difference(*enums)
    r = dup
    enums.each { |e| r = r - e }
    r
  end

  # Comparison operators: strict/non-strict subset and superset.
  def <(other)
    proper_subset?(other)
  end

  def <=(other)
    subset?(other)
  end

  def >(other)
    proper_superset?(other)
  end

  def >=(other)
    superset?(other)
  end

  # <=> per MRI: -1/0/1 when comparable as sub/superset, nil otherwise.
  def <=>(other)
    return nil if !other.is_a?(Set)
    return 0 if self == other
    return -1 if proper_subset?(other)
    return 1 if proper_superset?(other)
    nil
  end

  # Set#=== is membership.
  def ===(o)
    include?(o)
  end

  # Divide into a Set of Sets grouped by the block's value (1-arity form).
  def divide(&block)
    groups = {}
    each do |e|
      k = block.call(e)
      g = groups[k]
      if g.nil?
        g = Set.new
        groups[k] = g
      end
      g << e
    end
    result = Set.new
    groups.each { |_, g| result << g }
    result
  end

  # Recursively flatten nested Sets.
  def flatten
    # Recursion guard: a self-referential set (`set << set`) would otherwise recurse through #flatten
    # forever -> stack overflow / segfault. MRI raises ArgumentError for a recursive set. Mirror the
    # @__inspecting/@__comparing guards used elsewhere; a distinct set per nesting level means a Set that
    # merely appears twice (without a cycle) still flattens.
    raise ArgumentError.new("tried to flatten recursive Set") if @__flattening
    @__flattening = true
    result = Set.new
    each do |e|
      if e.is_a?(Set)
        e.flatten.each { |x| result << x }
      else
        result << e
      end
    end
    @__flattening = false
    result
  end

  def flatten!
    has_nested = false
    each do |e|
      if e.is_a?(Set)
        has_nested = true
      end
    end
    return nil if !has_nested
    replace(flatten)
    self
  end

  def join(sep = nil)
    to_a.join(sep)
  end

  # In-place filters. keep_if/delete_if return self; select!/reject! return
  # self when changed, nil otherwise.
  def keep_if(&block)
    arr = to_a
    i = 0
    while i < arr.length
      e = arr[i]
      @set.delete(e) if !block.call(e)
      i += 1
    end
    self
  end

  def delete_if(&block)
    arr = to_a
    i = 0
    while i < arr.length
      e = arr[i]
      @set.delete(e) if block.call(e)
      i += 1
    end
    self
  end

  # NOTE: the in-place filters iterate with WHILE loops, not to_a.each { }:
  # calling a captured &block param from inside another block is a known
  # self-host hazard (transform.rb FIXME; here block.call read always-truthy
  # inside the each-block, so reject! emptied the set).
  # (A pre-captured `n = size` compared after the loop read a CLOBBERED n --
  # the same local-across-statements clobber as String#__copy_raw's note --
  # so track changes with an in-loop flag instead.)
  def select!(&block)
    changed = 0
    arr = to_a
    i = 0
    while i < arr.length
      e = arr[i]
      if !block.call(e)
        @set.delete(e)
        changed = 1
      end
      i += 1
    end
    return nil if changed == 0
    self
  end

  def filter!(&block)
    select!(&block)
  end

  def reject!(&block)
    changed = 0
    arr = to_a
    i = 0
    while i < arr.length
      e = arr[i]
      if block.call(e)
        @set.delete(e)
        changed = 1
      end
      i += 1
    end
    return nil if changed == 0
    self
  end

  def collect!(&block)
    replace(to_a.map { |e| block.call(e) })
    self
  end

  def map!(&block)
    collect!(&block)
  end

  def to_set
    self
  end

  def hash
    to_a.map { |e| e.hash }.inject(0) { |a, b| a + b }
  end

  def eql?(other)
    self == other
  end
end
