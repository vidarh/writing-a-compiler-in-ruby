module Comparable
  def <(other)
    cmp = (self <=> other)
    return nil if cmp.nil?
    cmp < 0
  end

  def <=(other)
    cmp = (self <=> other)
    return nil if cmp.nil?
    cmp <= 0
  end

  def >(other)
    cmp = (self <=> other)
    return nil if cmp.nil?
    cmp > 0
  end

  def >=(other)
    cmp = (self <=> other)
    return nil if cmp.nil?
    cmp >= 0
  end

  def ==(other)
    return true if equal?(other)
    cmp = (self <=> other)
    return false if cmp.nil?
    cmp == 0
  end

  def between?(min, max)
    return false unless self >= min
    return false unless self <= max
    true
  end
end

class String
  include Comparable
end

class Symbol
  include Comparable
end
