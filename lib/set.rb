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
  def initialize
    @set = Hash.new # Told you it was dirty
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
  end

  def to_a
    @set.keys
  end

  def inspect
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
    out
  end

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
