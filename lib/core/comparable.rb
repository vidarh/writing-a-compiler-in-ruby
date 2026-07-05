module Comparable
  # clamp(min, max) or clamp(range): return self if it lies within [min, max], otherwise the nearer bound.
  # A Range argument may have a nil begin/end (open on that side).
  def clamp(min, max = nil)
    if max.nil? && min.is_a?(Range)
      lo = min.begin
      hi = min.end
    else
      lo = min
      hi = max
    end
    return lo if !lo.nil? && (self <=> lo) < 0
    return hi if !hi.nil? && (self <=> hi) > 0
    self
  end

  # MRI: the ordering operators RAISE ArgumentError when <=> returns nil
  # (incompatible comparison), rather than returning nil. (== stays false.)
  def __cmp_or_raise(other)
    cmp = (self <=> other)
    if cmp.nil?
      raise ArgumentError, "comparison of #{self.class} with #{other.class} failed"
    end
    cmp
  end

  def <(other)
    __cmp_or_raise(other) < 0
  end

  def <=(other)
    __cmp_or_raise(other) <= 0
  end

  def >(other)
    __cmp_or_raise(other) > 0
  end

  def >=(other)
    __cmp_or_raise(other) >= 0
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
