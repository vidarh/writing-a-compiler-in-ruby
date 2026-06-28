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

  # FIXME: Belongs in Enumerable
  def select
    a = []
    @set.each do |e,_|
      if yield(e)
        a << e
      end
    end
    a
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
end
