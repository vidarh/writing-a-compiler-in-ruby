# Enumerable module implementation
module Enumerable
  # lazy: a lazy enumerator over self (self must respond to #each).
  def lazy
    Enumerator::Lazy.new(self)
  end

  # all?/any?/none?/one? support three forms: a block, a pattern argument
  # (matched with #===), or neither (element truthiness).
  def all?(*pattern, &block)
    if pattern.length > 0
      pat = pattern[0]
      self.each do |item|
        return false if !(pat === item)
      end
    elsif block
      self.each do |item|
        return false if !block.call(item)
      end
    else
      self.each do |item|
        return false if !item
      end
    end
    true
  end


  def any?(*pattern, &block)
    if pattern.length > 0
      pat = pattern[0]
      self.each do |item|
        return true if pat === item
      end
    elsif block
      self.each do |item|
        return true if block.call(item)
      end
    else
      self.each do |item|
        return true if item
      end
    end
    false
  end


  def none?(*pattern, &block)
    !any?(*pattern, &block)
  end


  def one?(*pattern, &block)
    n = 0
    if pattern.length > 0
      pat = pattern[0]
      self.each do |item|
        if pat === item
          n += 1
          return false if n > 1
        end
      end
    elsif block
      self.each do |item|
        if block.call(item)
          n += 1
          return false if n > 1
        end
      end
    else
      self.each do |item|
        if item
          n += 1
          return false if n > 1
        end
      end
    end
    n == 1
  end


  def collect
    return to_enum(:collect) if !block_given?
    items = Array.new
    self.each do |item|
      items << yield(item)
    end
    return items
  end


  def detect(ifnone = nil)
    return to_enum(:detect) if !block_given?
    self.each do |item|
      if yield(item)
        return item
      end
    end
    if ifnone
      return ifnone.call
    end
    return nil
  end


  def each_cons(n)
    items = self.to_a
    ilength = items.length
    if ilength > n
      max_pairs = ilength.div(n)

      max_pairs.times do |i|
        yield(items[i..(i+n)])
      end
    end
  end


  # Yield each element n times (forever if n is nil); no-op / nil for an empty enumerable.
  def cycle(n = nil, &block)
    return to_enum(:cycle, n) if !block
    arr = to_a
    return nil if arr.length == 0
    if n.nil?
      while true
        arr.each { |x| block.call(x) }
      end
    else
      c = 0
      while c < n
        arr.each { |x| block.call(x) }
        c = c + 1
      end
    end
    nil
  end

  # map then drop falsy results.
  def filter_map(&block)
    return to_enum(:filter_map) if !block
    result = []
    each { |x| r = block.call(x); result << r if r }
    result
  end

  # [min, max].
  def minmax(&block)
    [min(&block), max(&block)]
  end

  # The element for which the block returns the smallest / largest value.
  def min_by
    return to_enum(:min_by) if !block_given?
    best = nil
    best_key = nil
    first = true
    each do |x|
      k = yield(x)
      if first || (k <=> best_key) < 0
        best = x
        best_key = k
        first = false
      end
    end
    best
  end

  def max_by
    return to_enum(:max_by) if !block_given?
    best = nil
    best_key = nil
    first = true
    each do |x|
      k = yield(x)
      if first || (k <=> best_key) > 0
        best = x
        best_key = k
        first = false
      end
    end
    best
  end

  # Group elements by the block's return value into a Hash of key => [elements].
  def group_by
    return to_enum(:group_by) if !block_given?
    h = {}
    each do |x|
      k = yield(x)
      h[k] = [] if !h.has_key?(k)
      h[k] << x
    end
    h
  end

  # Chunk CONSECUTIVE elements with the same block value into [key, [elements]] pairs.
  def chunk
    return to_enum(:chunk) if !block_given?
    result = []
    prev_key = nil
    cur = nil
    first = true
    each do |x|
      k = yield(x)
      if first || k != prev_key
        cur = [x]
        result << [k, cur]
        prev_key = k
        first = false
      else
        cur << x
      end
    end
    result
  end

  # Split into runs of consecutive elements: start a new chunk between adjacent elements a, b whenever the
  # block returns false for (a, b). Returns an Array of Arrays (MRI returns an Enumerator, but an Array
  # answers #to_a/#each the same way for the common `.chunk_while{...}.to_a` usage).
  def chunk_while
    items = to_a
    return [] if items.empty?
    result = []
    chunk = [items[0]]
    i = 1
    while i < items.length
      if yield(items[i - 1], items[i])
        chunk << items[i]
      else
        result << chunk
        chunk = [items[i]]
      end
      i = i + 1
    end
    result << chunk
    result
  end

  # The complement of chunk_while: start a new slice between adjacent elements a, b whenever the block
  # returns true for (a, b).
  def slice_when
    items = to_a
    return [] if items.empty?
    result = []
    chunk = [items[0]]
    i = 1
    while i < items.length
      if yield(items[i - 1], items[i])
        result << chunk
        chunk = [items[i]]
      else
        chunk << items[i]
      end
      i = i + 1
    end
    result << chunk
    result
  end

  # Iterates the given block for each slice of <n> elements.
  #
  # e.g.
  # (1..10).each_slice(3) {|a| p a}
  #   # outputs below
  #   [1, 2, 3]
  #   [4, 5, 6]
  #   [7, 8, 9]
  #   [10]
  def each_slice(n)
    # A slice size of 0 never advances `i` (i += n) -> infinite loop; a negative size runs it backwards.
    # MRI raises ArgumentError for both.
    raise ArgumentError, "invalid slice size" if n <= 0
    return to_enum(:each_slice, n) if !block_given?
    items = to_a
    i = 0
    len = items.length
    while i < len
      slice = []
      j = 0
      while j < n && i + j < len
        slice << items[i + j]
        j += 1
      end
      yield slice
      i += n
    end
    nil
  end


  def each_with_index
    return to_enum(:each_with_index) if !block_given?
    i = 0
    self.each do |item|
      yield(item, i)
      i += 1
    end
  end


  def entries
    return self.to_a
  end


#   def enum_cons
#   end

#   def enum_slice
#   end

#   def enum_with_index
#   end


  def find(ifnone = nil, &block)
    return self.detect(ifnone, &block)
  end


  def find_all
    found = Array.new
    self.each do |item|
      if yield(item)
        found << item
      end
    end
    return found
  end


#   def grep
#   end


  def include?(obj)
    return self.any?{ |item| item == obj }
  end


  # inject / reduce, all four forms: inject(sym), inject(init, sym), inject(init){blk}, inject{blk}.
  def inject(*args, &block)
    if block
      if args.length > 0
        acc = args[0]
        started = true
      else
        acc = nil
        started = false
      end
      each do |item|
        if !started
          acc = item
          started = true
        else
          acc = block.call(acc, item)
        end
      end
      acc
    else
      if args.length >= 2
        acc = args[0]
        sym = args[1]
        started = true
      else
        acc = nil
        sym = args[0]
        started = false
      end
      each do |item|
        if !started
          acc = item
          started = true
        else
          acc = acc.send(sym, item)
        end
      end
      acc
    end
  end
  alias reduce inject


  alias map collect


  def max
    result = nil
    seen = false
    each do |x|
      if !seen
        result = x
        seen = true
      elsif (x <=> result) > 0
        result = x
      end
    end
    result
  end


  alias member? include?


  def min
    result = nil
    seen = false
    each do |x|
      if !seen
        result = x
        seen = true
      elsif (x <=> result) < 0
        result = x
      end
    end
    result
  end


  def count
    n = 0
    each {|x| n = n + 1 }
    n
  end


  def partition
    yes = Array.new
    no  = Array.new
    each do |x|
      if yield(x)
        yes << x
      else
        no << x
      end
    end
    [yes, no]
  end


  def reject
    return to_enum(:reject) if !block_given?
    items = Array.new
    self.each do |item|
      if !yield(item)
        items << item
      end
    end
    return items
  end


  def select
    return to_enum(:select) if !block_given?
    items = Array.new
    self.each do |item|
      if yield(item)
        items << item
      end
    end
    return items
  end


  def sort
    a = Array.new
    each {|x| a << x }
    a.sort
  end


  def sort_by &block
    pairs = Array.new
    each {|x| pairs << [block.call(x), x] }
    sorted = pairs.sort {|a, b| a[0] <=> b[0] }
    sorted.map {|p| p[1] }
  end


  def to_a
    a = Array.new
    each {|x| a << x }
    a
  end


  def to_set
    Set.new(self)
  end


  def zip *others
    result = Array.new
    i = 0
    each do |x|
      row = [x]
      others.each {|o| row << o[i] }
      result << row
      i = i + 1
    end
    result
  end

  # Sum the elements starting from `init`. Non-float elements accumulate with plain #+; once a Float is
  # involved the running total switches to Kahan compensated summation, so a sum of floats matches MRI's
  # precise result (e.g. that dozen values sum to exactly 50.0, not 50.00000000000001).
  def sum init = 0
    acc = init
    comp = 0.0
    each do |x|
      if acc.is_a?(Float) || x.is_a?(Float)
        xf = x.is_a?(Float) ? x : x.to_f
        accf = acc.is_a?(Float) ? acc : acc.to_f
        y = xf - comp
        t = accf + y
        comp = (t - accf) - y
        acc = t
      else
        acc = acc + x
      end
    end
    acc
  end

  # NOTE: min_by/max_by/group_by are intentionally NOT defined here. The original "numargs off-by-one"
  # diagnosis was WRONG: the bare-variable-block-body bug (a block like {|x| x} compiled as a call) was
  # the real cause of the accumulator-yield crash, and it is now FIXED (transform.rb wraps lambda bodies
  # in :do, commit ded635a) -- `acc = acc + yield(x)` works. But defining min_by/group_by still regressed
  # enumerable/min_by_spec and group_by_spec FAIL->CRASH, because the SPECS exercise them deep inside the
  # mspec harness (should -> matcher -> lambda -> ... -> each -> Proc#call), which hits a SEPARATE deep
  # bug: the argument VALUE is clobbered to a count/index at depth (numargs is correct at 3). Re-add once
  # that arg-corruption-at-depth bug is fixed -- see the array-include-enumerable-broken memory for the
  # gdb-backed diagnosis (movl (%esi) with esi=tagged-int).

  def each_with_object obj
    return to_enum(:each_with_object, obj) if !block_given?
    each {|x| yield(x, obj) }
    obj
  end

  def flat_map
    result = Array.new
    each do |x|
      v = yield(x)
      if v.is_a?(Array)
        v.each {|e| result << e }
      else
        result << v
      end
    end
    result
  end

  # Hash of element -> occurrence count.
  def tally
    h = {}
    each do |x|
      c = h[x]
      if c.nil?
        h[x] = 1
      else
        h[x] = c + 1
      end
    end
    h
  end

  # first / first(n)
  def first(*n)
    if n.length == 0
      each do |x|
        return x
      end
      return nil
    end
    cnt = n[0]
    raise ArgumentError, "negative array size" if cnt < 0
    out = []
    each do |x|
      break if out.length >= cnt
      out << x
    end
    out
  end

  def grep(pattern, &block)
    out = []
    each do |x|
      if pattern === x
        if block
          out << block.call(x)
        else
          out << x
        end
      end
    end
    out
  end

  def grep_v(pattern, &block)
    out = []
    each do |x|
      if !(pattern === x)
        if block
          out << block.call(x)
        else
          out << x
        end
      end
    end
    out
  end

  def find_index(*obj, &block)
    i = 0
    if obj.length > 0
      target = obj[0]
      each do |x|
        return i if x == target
        i += 1
      end
    else
      return to_enum(:find_index) if !block
      each do |x|
        return i if block.call(x)
        i += 1
      end
    end
    nil
  end

  def take(n)
    raise ArgumentError, "attempt to take negative size" if n < 0
    out = []
    each do |x|
      break if out.length >= n
      out << x
    end
    out
  end

  def take_while(&block)
    return to_enum(:take_while) if !block
    out = []
    each do |x|
      break if !block.call(x)
      out << x
    end
    out
  end

  def drop(n)
    raise ArgumentError, "attempt to drop negative size" if n < 0
    out = []
    i = 0
    each do |x|
      out << x if i >= n
      i += 1
    end
    out
  end

  def drop_while(&block)
    return to_enum(:drop_while) if !block
    out = []
    dropping = true
    each do |x|
      dropping = false if dropping && !block.call(x)
      out << x if !dropping
    end
    out
  end

  # to_h over [key, value] pairs; with a block, the block maps each element
  # to a [key, value] pair first.
  def to_h(&block)
    h = {}
    each do |x|
      x = block.call(x) if block
      raise TypeError, "wrong element type #{x.class} (expected array)" if !x.is_a?(Array)
      raise ArgumentError, "wrong array length (expected 2, was #{x.length})" if x.length != 2
      h[x[0]] = x[1]
    end
    h
  end

  def uniq(&block)
    seen = {}
    out = []
    each do |x|
      k = x
      k = block.call(x) if block
      if !seen.key?(k)
        seen[k] = true
        out << x
      end
    end
    out
  end

  def minmax_by(&block)
    return to_enum(:minmax_by) if !block
    minx = nil
    miny = nil
    maxx = nil
    maxy = nil
    found = false
    each do |x|
      y = block.call(x)
      if !found
        minx = x
        miny = y
        maxx = x
        maxy = y
        found = true
      else
        if (y <=> miny) < 0
          minx = x
          miny = y
        end
        if (y <=> maxy) > 0
          maxx = x
          maxy = y
        end
      end
    end
    [minx, maxx]
  end

  def each_entry(&block)
    return to_enum(:each_entry) if !block
    each do |x|
      block.call(x)
    end
    self
  end
end

# Range loads before this file (see core.rb), so it cannot `include Enumerable` at its own definition.
# Reopen it here, now that Enumerable is fully defined, to give Range the full Enumerable surface
# (map/select/reject/reduce/min/max/min_by/partition/flat_map/each_slice/...). Range#each is a plain
# top-level-yield while-loop, so the captured-yield segfault that blocks this for Array does not apply.
class Range
  include Enumerable
end
