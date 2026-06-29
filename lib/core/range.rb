
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

  alias inspect to_s

  def exclude_end?
    @exclude_end == true
  end

  # Ruby: first/last with no arg return the endpoint; with a count n they return up to n elements from the
  # start/end as an Array. The no-arg call must still work (begin/end alias it). A 1-arg call previously
  # raised ArgumentError ("given 1, expected 0").
  def first(n = nil)
    return @min if n.nil?
    result = []
    each do |x|
      break if result.length >= n
      result << x
    end
    result
  end

  alias begin first

  def last(n = nil)
    return @max if n.nil?
    a = to_a
    start = a.length - n
    start = 0 if start < 0
    a[start..-1]
  end

  alias end last

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

  alias include? member?

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
