
# FIXME
# Initial implementation
# This implementation assumes simple ordering
class Range
  # NOTE: `include Enumerable` for Range is done at the END of lib/core/enumerable.rb, because Range is
  # loaded (core.rb) BEFORE Enumerable -- including it here would copy an as-yet-undefined module.
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
    return to_enum(:each) if !block_given?
    # Use #succ (not `+= 1`) so non-integer ranges work too. For a String/char range like ('0'..'5'),
    # `i += 1` invoked String#+(Integer) which read past the buffer and SEGFAULTED; Integer#succ is self+1
    # so integer ranges are unchanged.
    i = @min
    if @exclude_end
      while i < @max
        yield i
        i = i.succ
      end
    else
      while i <= @max
        yield i
        i = i.succ
      end
    end
  end

  # Yield every nth value from the start (n defaults to 1). Returns an Enumerator when block-less.
  def step(n = 1, &block)
    return to_enum(:step, n) if !block
    cur = @min
    if @exclude_end
      while cur < @max
        block.call(cur)
        cur = cur + n
      end
    else
      while cur <= @max
        block.call(cur)
        cur = cur + n
      end
    end
    self
  end

  # Binary search over an integer range. find-minimum mode: block returns true/false. find-any mode: block
  # returns a number (0 = found, narrowing on the sign). Returns nil if nothing matches.
  def bsearch(&block)
    lo = @min
    hi = @exclude_end ? @max : @max + 1
    found = nil
    while lo < hi
      mid = (lo + hi) / 2
      r = block.call(mid)
      if r == true
        found = mid
        hi = mid
      elsif r == false || r.nil?
        lo = mid + 1
      elsif r == 0
        return mid
      elsif r > 0
        lo = mid + 1
      else
        hi = mid
      end
    end
    found
  end

  def to_a
    a = []
    each do |v|
      a << v
    end
    a
  end

  # to_enum(meth=:each, *args): the default :each case keeps the specialised RangeEnumerator (external
  # iteration via next/peek); any other method delegates to a GenericEnumerator that calls it with a
  # block when forced. Without the meth/*args params, an Enumerable method's `to_enum(:each_slice, n)`
  # (the block-less path) hit this 0-arg version and raised "wrong number of arguments".
  def to_enum(meth = :each, *args)
    GenericEnumerator.new(self, meth, *args)
  end
  alias enum_for to_enum

  def lazy
    Enumerator::Lazy.new(self)
  end
end
