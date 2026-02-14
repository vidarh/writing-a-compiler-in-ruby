# FIXME
# This is all kinds of non-standard, but for
# now I only need very basic enumeration over
# Array and Range.
#


class Enumerator
  def size
    nil
  end

  def each
    if !block_given?
      return self
    end
    self
  end
end

class ArrayEnumerator < Enumerator
  def initialize(ary)
    @ary = ary
    @pos = 0
  end

  def next
    if @pos < @ary.length
      @pos += 1
      return @ary[@pos]
    else
      return nil
    end
  end
end

class IntegerEnumerator < Enumerator
  def initialize(int)
    @int = int
    @pos = 0
  end

  def size
    @int
  end

  def each
    if !block_given?
      return self
    end
    i = 0
    while i < @int
      yield i
      i += 1
    end
    @int
  end
end

# This is not a standard class. We do this because
# it's an easy way of getting basic Enumerator support
# without
class RangeEnumerator < Enumerator
  # @bug: Argument named "range" triggers the range constructor rewrite,
  # causing compilation failure (confirmed 2026-02-14).
  # See spec/bug_variable_name_collision_spec.rb
  def initialize(r)
    @min = r.first
    @max = r.last
    rewind
  end

  def rewind
    @cur = @min
  end

  def next
    if @cur <= @max
      cur = @cur
      @cur += 1
      return cur
    else
      # FIXME: This is wrong, but for the correct behaviour
      # we need exception support.
      return nil
    end
  end
end
