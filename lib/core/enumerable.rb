# Enumerable module implementation
module Enumerable
  # lazy: a lazy enumerator over self (self must respond to #each).
  def lazy
    Enumerator::Lazy.new(self)
  end

  def all?
    self.each do |item|
#      unless yield(item)
#        return false
#      end
    end
    return true
  end


  def any?
    self.each do |item|
      if yield(item)
        return true
      end
    end
    return false
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
  def each_slice
    # needs to be implemented
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


  def inject(initial = nil, &block)
#    unless initial
#      return self[1..-1].inject(self.first, &block)
#    end

    acc = initial
    self.each do |item|
      acc = yield(acc, item)
    end
    return acc
  end


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

  def sum init = 0
    acc = init
    each {|x| acc = acc + x }
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
end
