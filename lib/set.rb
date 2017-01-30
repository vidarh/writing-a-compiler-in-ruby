
#
# FIXME
# This is an awful, quick and dirty stub of a Set implementation
# to get some of the basics in place
#
class Set
  def initialize
    @set = Hash.new # Told you it was dirty
  end

  # FIXME: Belongs in Enumerable
  def select
    a = []
    @set.each do |e,_|
      a << e if yield(e) == true
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
    out = ""
    @set.each do |k,_|
      out << ", " if !out.empty?
      out << k
    end
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
      s << k
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

  def delete key
    @set.delete(key)
    self
  end
end
