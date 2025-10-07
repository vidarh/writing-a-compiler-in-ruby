
# FIXME
# Initial implementation
# This implementation assumes simple ordering
class Range
  def initialize _min, _max, exclude_end = false
    @min = _min
    @max = _max
    @exclude_end = exclude_end
  end

  def to_s
    if @exclude_end
      "#{@min}...#{@max}"
    else
      "#{@min}..#{@max}"
    end
  end

  def inspect
    to_s
  end

  def exclude_end?
    @exclude_end == true
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
    if @exclude_end
      return val >= @min && val < @max
    else
      return val >= @min && val <= @max
    end
  end

  def include? val
    member?(val)
  end

  def === (val)
    member?(val)
  end

  def each
    i = @min
    if @exclude_end
      while i < @max
        yield i
        i += 1
      end
    else
      while i <= @max
        yield i
        i += 1
      end
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
