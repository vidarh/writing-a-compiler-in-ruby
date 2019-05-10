
# FIXME
# Initial implementation
# This implementation assumes simple ordering
class Range
  def initialize _min, _max
    @min = _min
    @max = _max
  end

  def to_s
    "#{@min}..#{@max}"
  end

  def inspect
    to_s
  end

  def first
    @min
  end

  def last
    @max
  end

  # FIXME: This is hopelessly inadequate, but
  # tolerable for the case where we only use integer
  # ranges
  def member? val
    if !val
      return false
    end
    return val >= @min && val <= @max
  end

  def include? val
    member?(val)
  end

  def === (val)
    member?(val)
  end

  def each
    i = @min
    while i <= @max
      yield i
      i += 1
    end
  end

  def to_a
    a = []
    each do |v|
      a << v
    end
    a
  end

  def to_enum
    RangeEnumerator.new(self)
  end
end
