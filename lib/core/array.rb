# -*- coding: utf-8 -*-

class Array
  # FIXME: still need to make including modules work
  # include Enumerable

  # Override Class#new so an Array subclass whose #initialize skips `super` still gets valid internals:
  # run #__initialize (which sets @len/@ptr/@capacity = 0) on the fresh instance BEFORE the user
  # #initialize. Without this, `class MyArray < Array; def initialize(a,b); self << a << b; end` (no
  # super) uses uninitialised @len/@ptr and segfaults. Uses `allocate` (inherited Class#allocate) and
  # instance methods only -- no eigenclass `super`, which recurses on Array's metaclass.
  # Array.allocate must return a VALID empty array (MRI does), so that `Array.allocate` used directly
  # -- and any subclass instance -- has initialised internals. Replicate Class#allocate's body inline
  # (allocate @instance_size slots, set the class pointer) rather than calling `super`, which recurses
  # on Array's metaclass, then run #__initialize.
  def self.allocate
    ob = nil
    %s(assign ob (__array (index self 1)))
    %s(assign (index ob 0) self)
    ob.__initialize
    ob
  end

  def self.new *__copysplat
    ob = allocate
    ob.initialize(*__copysplat)
    ob
  end

  # Let's start with the basics:

  # FIXME: initialize should take two optional arguments,
  # but we don't yet handle initializers, so not supporting that
  # for now.
  def initialize *__copysplat
    # FIXME: See notes in lib/core/core.rb regarding bootstrapping
    # of splat handling, which causes the annoyance below:
    #
    # This would work better/be simpler with tagger pointers, as in
    # that case, using Fixnum would not trigger object creation.
    # A cleaner option (over using low level stuff in Array) may be
    # to not use Fixnum#new in __int, but wire that up specially.
    #
    # We'd still be limited in what to do here, but not as strictly.
    #
    __initialize
    %s(if (gt numargs 2) (callm self __copy_init ((index __copysplat 0))))
  end

  def __copy_init other
    __grow(other.__get_raw)
  end

  def capacity
    %s(__int @capacity)
  end

  #FIXME: Private. Assumes idx < @len && idx >= 0
  def __get(idx)
    %s(index @ptr idx)
  end

  # --------------------------------------------------

  # FIXME: Belongs in Enumerable
  def find # FIXME: ifnone
    each do |e|
      r = yield(e)
      return e if r != false
    end
    return nil
  end

  # FIXME: Belongs in Enumerable
  def include? other
    each do |e|
      return true if e == other
    end
    return false
  end

  # FIXME: Belongs in enumerable
  def reject
    a = self.class.new
    each do |item|
      if !yield(item)
        a << item
      end
    end
    a
  end

  # Inverse of reject - keeps items where block returns true
  def select
    a = self.class.new
    each do |item|
      if yield(item)
        a << item
      end
    end
    a
  end

  alias find_all select

  # FIXME: Cut and paste from Enumerable
  def collect
    if block_given?
      items = Array.new
      each do |item|
        items << yield(item)
      end
      return items
    else
      return self
    end
  end

  alias map collect

  # Array#sum is defined directly here (Array cannot `include Enumerable` -- those methods segfault on
  # call; see the array-include-enumerable-broken note). NOTE: only non-yielding helpers are safe to add
  # this way -- a method that does `yield` inside an `each {}` block (min_by/group_by/each_with_object/
  # flat_map) currently segfaults on an Array (captured-yield-through-Array#each bug), though the same
  # code works on Set. So those are intentionally NOT added here yet.
  def sum init = 0
    acc = init
    each {|x| acc = acc + x }
    acc
  end


  # FIXME: Cut and paste from Enumerable
  def detect(ifnone = nil)
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

  # FIXME: Cut and paste from Enumerable
  def each_with_index(&block)
    self.each_index do |i|
      block.call(self[i], i)
    end
  end


  # Set Intersection.
  # Returns a new array containing elements common to the two arrays, with no duplicates.
#  def &(other_array)
#    return self.uniq.select{|item| other_array.include?(item)}
#  end

  # Repetition.
  # With a String argument, equivalent to self.join(str).
  # Otherwise, returns a new array built by concatenating the int copies of self.
#  def *(amount)
#    if amount.is_a?(String)
#      return self.join(amount)
#    elsif amount.is_a?(Fixnum)
#      mul_array = Array.new(self)
#      amount.times do
#        mul_array += self
#      end
#      return mul_array
#    end
#  end


  # Concatenation.
  # Returns a new array built by concatenating the two arrays together
  # to produce a third array.
  def +(other_array)
    added = self.dup
    added.concat(other_array)
    return added
  end

  # Array Difference.
  # Returns a new array that is a copy of the original array,
  # removing any items that also appear in other_array.
  # (If you need set-like behavior, see the library class Set.)
  # FIXME: Merely uncommenting this (without calling it) causes weird errors.
  # def -(other_array)
  #  self.reject do |item| 
  #    other_array.include?(item)
  #  end
  #end

  # Pushes the given object on to the end of this array. This expression
  # returns the array itself, so several appends may be chained together.
  def <<(obj)
    %s(if (ge @len @capacity) (callm self __grow ((mul (add @len 1) 2))))
    %s(assign (index @ptr @len) obj)
    %s(assign @len (add @len 1))
    self
  end


  # Comparison.
  # Returns an integer (-1, 0, or +1) if this array is less than, equal to,
  # or greater than other_array.
  # Each object in each array is compared (using <=>).
  # If any value isn‘t equal, then that inequality is the return value.
  # If all the values found are equal, then the return is based on a comparison
  # of the array lengths. Thus, two arrays are ``equal’’ according to Array#<=>
  # if and only if they have the same length and the value of each element is
  # equal to the value of the corresponding element in the other array.
  # Comparison: element-by-element using <=>, returning the first non-zero result; if all compared
  # elements are equal, the shorter array is "less". Returns nil if other is not an Array or an element
  # comparison is nil. Needed for sorting arrays-of-arrays (e.g. collected yielded args) which previously
  # raised "undefined method '<=>'".
  def <=>(other)
    # Identity short-circuit: a <=> a is 0, and this stops infinite recursion (-> segfault) when an
    # array contains itself (recursive_array <=> recursive_array compares element i==self forever).
    return 0 if self.equal?(other)
    if !other.is_a?(Array)
      return nil if !other.respond_to?(:to_ary)
      other = other.to_ary
    end
    # Recursion guard for two DIFFERENT mutually-recursive arrays: treat the cyclic back-edge as equal
    # (0) so the comparison terminates (mirrors the @__comparing guard in #==).
    return 0 if @__comparing
    @__comparing = true
    len = self.size < other.size ? self.size : other.size
    result = nil
    decided = false
    i = 0
    while i < len
      cmp = (self[i] <=> other[i])
      if cmp.nil?
        result = nil
        decided = true
        i = len
      elsif cmp != 0
        result = cmp
        decided = true
        i = len
      else
        i = i + 1
      end
    end
    result = (self.size <=> other.size) if !decided
    @__comparing = false
    result
  end


  # Equality.
  # Two arrays are equal if they contain the same number of elements and if each
  # element is equal to (according to Object.==) the corresponding element in the
  # other array.
  def ==(other)
    # Identity short-circuit: an array is always == to itself. Besides being a fast path, this is
    # what prevents infinite recursion (-> stack overflow / segfault) on self-referential arrays:
    # rubyspec compares the SAME recursive array on both sides (e.g. empty.uniq == [empty]), so the
    # recursive element hits this identity check instead of descending forever.
    return true if self.equal?(other)

    if !other.is_a?(Array)
      return false
    end

    if self.size != other.size
      return false
    end

    # Recursion guard: if self is already mid-comparison higher up the stack, this is a cyclic
    # (self-referential) structure -- treat the back-edge as equal so we terminate instead of
    # recursing forever (-> heap exhaustion / SIGSEGV). The flag is a plain ivar, set on entry and
    # cleared on exit, so no global state is needed (a load-time global init breaks core bootstrap).
    return true if @__comparing
    @__comparing = true
    result = true
    self.each_index do |i|
      if self[i] != other[i]
        result = false
      end
    end
    @__comparing = false
    result
  end


  def self.[](*elements)
    a = self.new
    a.concat(elements)
    a
  end

  # FIXME: Should be private
  # Takes an index into an array, which may be
  # negative, and returns the actual offset
  # of -1 if the index is out of bounds.
  def __offset_to_pos(idx)
    %s(assign idx (callm idx __get_raw))
    %s(if (lt idx 0)
         (do
            (assign idx (add @len idx))
            (if (lt idx 0) (return -1)
               )))

    %s(if (ge idx @len)
         (return -1))

    %s(return idx)
  end

  # FIXME: Private.
  #
  # Handles #[](idx) where "idx" is a Range.
  def __range_get(idx)
     start = idx.first
     xend  = idx.last
     %s(assign start (__int (callm self __offset_to_pos(start))))
     %s(assign xend  (__int (callm self __offset_to_pos(xend))))

     if (start < 0)
       return Array.new
     end

     if xend < 0
       xend = length - 1
     end

     # For an exclusive range (1...3) stop one before the end index.
     if idx.exclude_end?
       xend = xend - 1
     end

     # Single item gets passed back to #[]
     #return self.[](start) if start == xend

     # FIXME
     # This is an inefficient first pass vs. allocating sufficient capacity
     # and copying straight over, but will do for now.
     tmp = Array.new

     while start <= xend
       tmp << self[start]
       start += 1
     end
     return tmp
  end

  #
  # The non-Range version of Array#[] ends up getting called by a
  # lot of really low level code, and so anything trying to call any
  # other Ruby code, to e.g. use Symbol's or similar, is likely to fail.
  #
  def [](idx)

    return __range_get(idx) if idx.is_a?(Range)

    %s(assign idx (callm self __offset_to_pos (idx)))

    # Bounds check - if still out of bounds after handling negative integers
    # and the like with __offset_to_pos(), we return nil.
    %s(if (or (or 
               (eq @ptr 0) 
               (ge idx @len)
               ) 
           (lt idx 0))
         (return nil))

    %s(assign tmp (callm self __get (idx)))
    %s(if (eq tmp 0) (return nil) (return tmp))
  end


  # Element Assignment.
  # Sets the element at index, or replaces a subarray starting at start and
  # continuing for length elements, or replaces a subarray specified by range.
  # If indices are greater than the current capacity of the array, the array grows
  # automatically. A negative indices will count backward from the end of the array.
  # Inserts elements if length is zero. If nil is used in the second and third form,
  # deletes elements from self. An IndexError is raised if a negative index points
  # past the beginning of the array. See also Array#push, and Array#unshift.
  # a[index] = obj / a[start, length] = obj / a[range] = obj. The last argument is the value; for the
  # span forms it may be an Array (spliced in) or a scalar (inserted as one element).
  def []=(*args)
    argc = args.length
    obj = args[argc - 1]
    if argc == 3
      return __span_set(args[0], args[1], obj)
    end
    idx = args[0]
    if idx.is_a?(Range)
      l = length
      b = idx.first
      e = idx.last
      b = l + b if b < 0
      e = l + e if e < 0
      count = idx.exclude_end? ? (e - b) : (e - b + 1)
      count = 0 if count < 0
      return __span_set(b, count, obj)
    end
    __index_set(idx, obj)
  end

  # a[i] = obj for an Integer index. A negative index counts from the end; too-negative raises
  # IndexError. Writing past the end grows (the gap reads as nil, since the buffer is zeroed).
  def __index_set(idx, obj)
    len = length
    if idx < 0
      idx = len + idx
      raise IndexError.new("index too small for array; minimum #{0 - len}") if idx < 0
    end
    %s(assign idx (callm idx __get_raw))
    %s(if (ge idx @capacity) (callm self __grow (idx)))
    %s(if (ge idx @len) (assign @len (add idx 1)))
    %s(assign (index @ptr idx) obj)
    obj
  end

  # Replace the `count` elements starting at `start` with `obj` (an Array is spliced element-wise, a
  # scalar is inserted as one element). Rebuilds via head + inserted + tail and replace().
  def __span_set(start, count, obj)
    l = length
    start = l + start if start < 0
    raise IndexError.new("index #{start} out of array bounds") if start < 0
    count = 0 if count < 0
    ins = obj.is_a?(Array) ? obj : [obj]
    result = []
    i = 0
    while i < start
      result << (i < l ? self[i] : nil)
      i = i + 1
    end
    j = 0
    while j < ins.length
      result << ins[j]
      j = j + 1
    end
    i = start + count
    while i < l
      result << self[i]
      i = i + 1
    end
    replace(result)
    obj
  end



  # Calculates the set of unambiguous abbreviations for the strings in self.
  # If passed a pattern or a string, only the strings matching the pattern or starting
  # with the string are considered.
  def abbrev(pattern = nil)
    %s(puts "Array#abbrev not implemented")
  end

  def slice(idx)
    self[idx]
  end

  # Searches through an array whose elements are also arrays comparing obj with the
  # first element of each contained array using obj.==. Returns the first contained
  # array that matches (that is, the first associated array), or nil if no match is found.
  # See also Array#rassoc.
  def assoc(obj)
    self.each do |item|
      if item.is_a?(Array)
        if item.first == obj
          return item
        end
      end
    end

    return nil
  end


  # Returns the element at index. A negative index counts from the end of self.
  # Returns nil if the index is out of range. See also Array#[].
  # (Array#at is slightly faster than Array#[], as it does not accept ranges and so on.)
  def at(idx)
    if !idx.is_a?(Integer)
      if !idx.respond_to?(:to_int)
        raise TypeError.new("no implicit conversion of #{idx.class} into Integer")
      end
      idx = idx.to_int
    end
    self[idx]
  end


  # Removes all elements from self.
  def clear
    raise FrozenError.new("can't modify frozen Array: #{inspect}") if frozen?
    # FIXME: consider whether to actually shrink
    %s(assign @len 0)
    self
  end


  # Invokes the block once for each element of self, replacing the element with the value
  # returned by block.
  # See also Enumerable#collect.
  def collect!
    # replace all elements with new ones by calling block on each
  end


  # Returns a copy of self with all nil elements removed.
  def compact
    return self.reject{|item| item.nil?}
  end


  # Removes nil elements from array. Returns nil if no changes were made.
  def compact!
    n = self.size
    kept = self.select {|x| x != nil }
    return nil if kept.size == n
    replace(kept)
    self
  end

  # Appends the elements in other_array to self.
  def concat(other_array)
    added = self
    other_array.each do |item|
      added << item
    end
    return added
  end


  def dclone
    %s(puts "Array#dclone not implemented")
  end


  # Deletes items from self that are equal to obj.
  # If the item is not found, returns nil. If the optional code block is given,
  # returns the result of block if the item is not found.
  def delete(obj)
    src  = 0
    dest = 0
    len  = length

    while src < len
      sob = self[src]
      if sob != obj
        if src != dest
          self[dest] = sob
        end
        dest += 1
      end
      src += 1
    end
    %s(assign @len (callm dest __get_raw))
    obj
  end


  # Deletes the element at the specified index, returning that element,
  # or nil if the index is out of range. See also Array#slice!.
  def delete_at(idx)
    return nil if idx < 0

    l = length
    return nil if idx >= l

    e = self[idx]

    x = self
    while idx < l
      # FIXME: This is parsed wrong:
      # self[idx] = self[idx+1]

      o = x[idx+1]
      x[idx] = o
      idx += 1
    end

    %s(assign @len (sub @len 1))
    return e
  end


  # Deletes every element of self for which block evaluates to true.
  def delete_if
    kept = []
    each {|x| kept << x if !yield(x) }
    replace(kept)
    self
  end

  # FIXME: Highly inefficient...
  def dup
    a = self.class.new
    each do |e|
      a << e
    end
    a
  end

  # Calls block once for each element in self,
  # passing that element as a parameter.
  def each &block
    # Without a block, #each returns an Enumerator (Ruby semantics). Previously `block.arity` below
    # was called with no block and segfaulted -- the root of a large cluster of array/enumerable spec
    # crashes. Use block_given? (touching the &block var itself when none was passed also segfaults).
    return ArrayEnumerator.new(self) if !block_given?
    i = 0
    a = block.arity
    s = self.size

    if a == 1
      while i < s
        el = self[i]
        yield(el)
        i += 1
      end
      return nil
    end

    while i < s
      el = self[i]
      if el.is_a?(Array)
        yield(*el)
      else
        yield(el)
      end
      i += 1
    end
    return nil
  end


  alias member? include?


  # Same as Array#each, but passes the index of the element
  # instead of the element itself.
  def each_index
    i = 0
    while i < self.size
      yield(i)
      i += 1
    end
  end

  # Returns true if self array contains no elements.
  def empty?
    return self.size == 0
  end


  # Returns true if array and other are the same object,
  # or are both arrays with the same content.
  def eql?(other_array)
    return true if (self.object_id == other_array.object_id)
    return false if !other_array.kind_of?(Array)
    return false if self.length != other_array.length

    i = 0
    l = self.length
    while i < l
      # FIXME: Recursion
      return false if self[i] != other_array[i]
      i += 1
    end

    return true
  end


  # Tries to return the element at position index.
  # If the index lies outside the array, the first form throws an IndexError
  # exception, the second form returns default, and the third form returns
  # the value of invoking the block, passing in the index. Negative values of
  # index count from the end of the array.
  # fetch(index) / fetch(index, default) / fetch(index) { |i| ... } -> element at index. A negative
  # index counts from the end. When out of range: a block (passed the original index) takes precedence,
  # else the default argument is returned, else IndexError is raised.
  def fetch(idx, *rest)
    len = length
    i = idx < 0 ? len + idx : idx
    return self[i] if i >= 0 && i < len
    return yield(idx) if block_given?
    return rest[0] if rest.length > 0
    raise IndexError.new("index #{idx} outside of array bounds: #{0 - len}...#{len}")
  end


  # fill(obj) / fill(obj, start) / fill(obj, start, len) / fill(obj, range) and the block forms
  # fill { |i| } / fill(start) { } / fill(start, len) { } / fill(range) { }. Fills in place, returns self.
  def fill(*args, &block)
    n = length
    if block
      spec0 = args[0]
      spec1 = args[1]
    else
      obj = args[0]
      spec0 = args[1]
      spec1 = args[2]
    end
    if spec0.is_a?(Range)
      s = spec0.begin
      s = n + s if s < 0
      e = spec0.exclude_end? ? spec0.end : spec0.end + 1
    else
      s = spec0.nil? ? 0 : spec0
      s = n + s if s < 0
      e = spec1.nil? ? n : s + spec1
    end
    i = s
    while i < e
      self[i] = block ? block.call(i) : obj
      i = i + 1
    end
    self
  end

  # Elements from the front while the block is true.
  def take_while
    result = []
    each do |x|
      break if !yield(x)
      result << x
    end
    result
  end

  # Elements after the leading run for which the block is true.
  def drop_while
    result = []
    dropping = true
    each do |x|
      dropping = false if dropping && !yield(x)
      result << x if !dropping
    end
    result
  end

  # Yield each element n times (forever if n is nil). No-op on an empty array.
  def cycle(n = nil, &block)
    return to_enum(:cycle, n) if !block
    return nil if length == 0
    if n.nil?
      while true
        each { |x| block.call(x) }
      end
    else
      c = 0
      while c < n
        each { |x| block.call(x) }
        c = c + 1
      end
    end
    nil
  end


  # Returns the first element, or the first n elements, of the array.
  # If the array is empty, the first form returns nil, and the second form returns an empty array.
  def first(n = nil)
    if n
      if self.empty?
        return Array.new
      end

      first_n = Array.new
      if n >= self.size
        return Array.new(self)
      end

      n.times do |i|
        first_n << self[i]
      end
      return first_n
    end

    if self.empty?
      return nil
    else
      return self[0]
    end
  end

  # Returns the object in the array with the maximum value
  # Uses <=> for comparison
  def max
    return nil if self.empty?

    max_val = self[0]
    i = 1
    s = self.size

    while i < s
      el = self[i]
      if (el <=> max_val) > 0
        max_val = el
      end
      i += 1
    end

    max_val
  end

  # Returns the object in the array with the minimum value
  # Uses <=> for comparison
  def min
    return nil if self.empty?

    min_val = self[0]
    i = 1
    s = self.size

    while i < s
      el = self[i]
      if (el <=> min_val) < 0
        min_val = el
      end
      i += 1
    end

    min_val
  end

  # Returns true if any element matches the given block (or is truthy if no block given)
  def any?
    i = 0
    s = self.size
    while i < s
      el = self[i]
      return true if yield(el)
      i += 1
    end
    false
  end

  # Returns true if all elements match the given block (or are truthy if no block given)
  def all?
    i = 0
    s = self.size
    while i < s
      el = self[i]
      return false if !yield(el)
      i += 1
    end
    true
  end

  # Returns true if no elements match the given block (or are truthy if no block given)
  def none?
    i = 0
    s = self.size
    while i < s
      el = self[i]
      return false if yield(el)
      i += 1
    end
    true
  end


  # Returns a new array that is a one-dimensional flattening of this array (recursively).
  # That is, for every element that is an array, extract its elements into the new array.
  # A copy with the first `count` elements moved to the end (negative rotates the other way).
  def rotate(count = 1)
    n = length
    return dup if n == 0
    c = count % n
    self[c..-1] + self[0...c]
  end

  def rotate!(count = 1)
    replace(rotate(count))
    self
  end

  # Nested element access: dig(a, b, ...) == self[a].dig(b, ...), stopping at the first nil.
  def dig(key, *rest)
    v = self[key]
    return v if rest.empty? || v.nil?
    v.dig(*rest)
  end

  # Binary search over a sorted array. find-minimum mode: block returns true/false, returns the first
  # element for which it is true. find-any mode: block returns a number, returns an element for which it
  # is 0 (narrowing on the sign). Returns nil if nothing matches. The array must be sorted for the mode.
  def bsearch(&block)
    lo = 0
    hi = length
    found = nil
    while lo < hi
      mid = (lo + hi) / 2
      v = self[mid]
      r = block.call(v)
      if r == true
        found = v
        hi = mid
      elsif r == false || r.nil?
        lo = mid + 1
      elsif r == 0
        return v
      elsif r > 0
        lo = mid + 1
      else
        hi = mid
      end
    end
    found
  end

  # All n-element combinations (order within the array preserved, no repeats). With a block, yields each
  # and returns self; without a block returns the array of combinations (answers .to_a/.each like MRI's
  # Enumerator for the common use).
  def combination(n, &block)
    result = []
    if n >= 0 && n <= length
      __combination_into(n, 0, [], result)
    end
    if block
      result.each { |c| block.call(c) }
      self
    else
      result
    end
  end

  def __combination_into(n, start, current, result)
    if current.length == n
      result << current.dup
      return
    end
    i = start
    while i < length
      current << self[i]
      __combination_into(n, i + 1, current, result)
      current.pop
      i = i + 1
    end
  end

  # Cartesian product of self with the given arrays: every [a, b, ...] with a from self, b from others[0]...
  def product(*others)
    result = [[]]
    arrays = [self]
    others.each { |o| arrays << o }
    arrays.each do |arr|
      nxt = []
      result.each do |combo|
        arr.each do |elem|
          nxt << (combo + [elem])
        end
      end
      result = nxt
    end
    result
  end

  # Random element(s). sample -> one element (nil if empty); sample(n) -> up to n distinct elements. A
  # `random:` option (an object responding to #rand) supplies the RNG, else Random.rand is used.
  def sample(*args)
    n = nil
    rng = nil
    args.each do |a|
      if a.is_a?(Hash)
        rng = a[:random]
      else
        n = a
      end
    end
    if n.nil?
      return nil if length == 0
      return self[__sample_index(length, rng)]
    end
    count = n
    count = length if count > length
    pool = []
    i = 0
    while i < length
      pool << self[i]
      i = i + 1
    end
    result = []
    k = 0
    while k < count
      j = __sample_index(pool.length, rng)
      result << pool[j]
      pool.delete_at(j)
      k = k + 1
    end
    result
  end

  def __sample_index(m, rng)
    rng.nil? ? Random.rand(m) : rng.rand(m)
  end

  def flatten level=nil
    #STDERR.puts "FLATTEN: #{self.inspect}"
    # Cycle guard: a self-referential array would recurse forever through e.flatten -> segfault.
    # MRI raises ArgumentError "tried to flatten recursive array". Track the in-progress flatten with
    # a per-array flag; re-entering flatten on the same array raises.
    if @__flattening
      raise ArgumentError, "tried to flatten recursive array"
    end
    @__flattening = true
    n = []
    l = level
    each do |e|
      l
      n
      if e.is_a?(Array)
        # FIXME: the "e.flatten(l-1)" was mis-parsed without the whitespace.
        if l
          e = e.flatten(l - 1) if l > 1
        else
          e = e.flatten
        end
        n.concat(e)
      else
        n << e
      end
    end
    @__flattening = false
    n
  end


  # Flattens self in place. Returns nil if no modifications were made.
  # (i.e., array contains no subarrays.)
  def flatten!(level = nil)
    nested = false
    each do |e|
      nested = true if e.is_a?(Array)
    end
    return nil if !nested
    replace(flatten(level))
    self
  end


  # FIXME: local @frozen ivar is a per-class workaround; the proper mechanism is the slot-1
  # flags word so freeze works uniformly -- see the object layout docs in lib/core/object.rb.
  def freeze
    @frozen = true
    self
  end

  def frozen?
    @frozen ? true : false
  end


  # Compute a hash-code for this array. Two arrays with the same content will have
  # the same hash code (and will compare using eql?).
  #
  # Uses djb hash
  def hash
    # Use s-expressions to avoid overflow detection during hash computation
    # Hash values are allowed to overflow and wrap around in 32-bit space
    # Pattern copied from String#hash
    %s(assign h 5381)
    %s(assign h (add (mul h 33) (callm self length)))
    each do |c|
      %s(assign h (add (mul h 33) (callm c hash)))
    end
    %s(__int h)
  end


  # Returns the index of the first object in self such that is == to obj.
  # Returns nil if no match is found.
  def index(obj)
    i = 0
    l = length
    while (i < l)
      if self[i] == obj
        return i
      end
      i+=1
    end
    # FIXME: This seems to fail when compiling the compiler.
    #self.each_with_index do |item, idx|
    #  if item == obj
    #    return index
    #  end
    #end

    return nil
  end


  # Replaces the contents of self with the contents of other_array,
  # truncating or expanding if necessary.
  def replace(other_array)
    # FIXME: Initial, crude, slow version.

    # Truncate current version, without resetting capacity.
    %s(assign @len 0)

    # Copy other_array.
    other_array.each {|item| self << item }
  end


  # insert(index, *objects) -> inserts the objects before the element at index (a non-negative index
  # pads with nils if it is past the end; a negative index inserts AFTER that element, so -1 appends).
  # Raises IndexError if the negative index is out of bounds. Modifies self in place and returns self.
  def insert(idx, *objects)
    return self if objects.empty?
    len = length
    if idx < 0
      pos = len + idx + 1
      if pos < 0
        raise IndexError.new("index #{idx} too small for array; minimum #{0 - len - 1}")
      end
    else
      pos = idx
    end

    result = []
    i = 0
    # Head: elements before pos, padding with nil when pos is past the current end.
    while i < pos
      if i < len
        result << self[i]
      else
        result << nil
      end
      i = i + 1
    end
    # The inserted objects.
    j = 0
    while j < objects.length
      result << objects[j]
      j = j + 1
    end
    # Tail: the remaining original elements from pos onward.
    while i < len
      result << self[i]
      i = i + 1
    end

    replace(result)
    self
  end


  # Create a printable version of array.
  def inspect
    # Cycle guard: a self-referential array (a = []; a << a) would otherwise recurse forever through
    # a.inspect -> stack overflow / segfault. MRI prints "[...]" for an array already being inspected.
    # Track that with a per-array flag set for the duration of this call.
    if @__inspecting
      return "[...]"
    end
    @__inspecting = true
    str = "["
    first = true
    each do |a|
      if !first
        str << ", "
      else
        first = false
      end
      str << a.inspect
    end
    str << "]"
    @__inspecting = false
    str
  end


  # Returns a string created by converting each element of the array to a string,
  # separated by sep.
  def join(sep) # = nil)
    join_str = ""
    size = self.size
    sep = sep.to_s
    self.each do |item|
      if !join_str.empty?
        join_str << sep
      end
      join_str << item.to_s
    end
    join_str
  end


  # Returns the last element(s) of self.
  # If the array is empty, the first form returns nil.
  def last(n = nil)
    if n
      if n >= self.size
        return Array.new(self)
      end

      last_n = Array.new
      delta = self.size - n
      n.times do |i|
        last_n << self[i + delta]
      end
      return last_n
    end

    if self.empty?
      return nil
    else
      return self[-1]
    end
  end


  # Returns the number of elements in self. May be zero.
  def length
    %s(__int @len)
  end


  # Invokes block once for each element of self.
  # Creates a new array containing the values returned by the block.
  # See also Enumerable#collect.
  def collect!
    i = 0
    n = self.size
    while i < n
      self[i] = yield(self[i])
      i += 1
    end
    self
  end


  # Invokes block once for each element of self.
  # Creates a new array containing the values returned by the block.
  # See also Enumerable#collect.
  def map!
    i = 0
    n = self.size
    while i < n
      self[i] = yield(self[i])
      i += 1
    end
    self
  end


  # Returns the number of non-nil elements in self. May be zero.
  def nitems
    return self.select{|item| item != nil}.size
  end


  def pack
    %s(puts "Array#pack not implemented")
  end


  # Removes the last element from self and returns it,
  # or nil if the array is empty.
  def pop
    if self.empty?
      return nil
    else
      last_element = self.last
      %s(assign @len (sub @len 1))
      return last_element
    end
  end


  def pretty_print(q)
    %s(puts "Array#pretty_print not implemented")
  end


  # Append.
  # Pushes the given object(s) on to the end of this array.
  # This expression returns the array itself, so several appends may be chained together.
  def push(*objects)
    i = 0
    n = objects.length
    while i < n
      self << objects[i]
      i = i + 1
    end
    self
  end


  def quote
    %s(puts "Array#quote not implemented")
  end


  # Searches through the array whose elements are also arrays.
  # Compares key with the second element of each contained array using ==.
  # Returns the first contained array that matches. See also Array#assoc.
  def rassoc(key)
    self.each do |item|
      if item.is_a?(Array)
        if item[1] == key
          return item
        end
      end
    end

    return nil
  end


  # Equivalent to Array#delete_if, deleting elements from self for which the
  # block evaluates to true, but returns nil if no changes were made.
  # Also see Enumerable#reject.
  def reject!
    n = self.size
    kept = []
    each {|x| kept << x if !yield(x) }
    return nil if kept.size == n
    replace(kept)
    self
  end


  # Returns a new array containing self‘s elements in reverse order.
  def reverse
    self.dup.reverse!
  end


  # Reverses self in place.
  def reverse!
    i = 0
    j = length - 1

    while i < j
      tmp = self[i]
      self[i] = self[j]
      self[j] = tmp
      i += 1
      j -= 1
    end
    self
  end


  # Same as Array#each, but traverses self in reverse order.
  def reverse_each(&block)
    self.reverse.each(&block)
  end


  # Returns the index of the last object in array == to obj. Returns nil if no match is found.
  # Last index of obj (==), or of the last element for which the block is true.
  def rindex(*args, &block)
    found_index = nil
    if block
      each_with_index { |item, idx| found_index = idx if block.call(item) }
    else
      obj = args[0]
      each_with_index { |item, idx| found_index = idx if item == obj }
    end
    found_index
  end

  # count -> size; count(obj) -> number == obj; count { |x| } -> number for which the block is true.
  def count(*args, &block)
    if block
      n = 0
      each { |x| n = n + 1 if block.call(x) }
      n
    elsif args.length > 0
      obj = args[0]
      n = 0
      each { |x| n = n + 1 if x == obj }
      n
    else
      length
    end
  end


  # Returns the first element of self and removes it (shifting all other elements down by one).
  # Returns nil if the array is empty.
  def shift
    if self.empty?
      return nil
    else
      first_element = self.first
      self.delete_at(0)
      return first_element
    end
  end


  # Alias for length
  def size
    return self.length
  end

  # FIXME: This belongs in Enumberable once "include" works.
  def partition &block
    trueArr = []
    falseArr = []

    each do |e|
      if block.call(e)
        trueArr << e
      else
        falseArr << e
      end
    end

    [trueArr,falseArr]
  end

  # FIXME: This belongs in Enumberable once "include" works.
  #
  # FIXME: This implementation is horrible in many ways,
  #  as it's the most naive way possible of implementing
  #  quicksort. It *will* perform badly. Basic improvements to
  #  look at (precise set of what's worth depends on constant
  #  overheads, so needs benchmarks):
  #   - Other sorts may work better once sub-arrays are small enough
  #   - In place partitioning after initial copy.
  #   - Proper pivot selection to reduce chance of hitting worst case
  def sort_by &block
    return self if length <= 1
    pivot_el = self[0]
    pivot = block.call(pivot_el)
    part  = self[1..-1].partition {|e| block.call(e) < pivot }

    left  = part[0].sort_by(&block)
    right = part[1].sort_by(&block)

    left + [pivot_el] + right
  end

  # FIXME: Inefficient, and doesn't support providing a block
  #
  # Returns a new array created by sorting self.
  # Comparisons for the sort will be done using the <=> operator or using
  # an optional code block. The block implements a comparison between a and b,
  # returning -1, 0, or +1.
  # See also Enumerable#sort_by.
  def sort &block
    return self if length <= 1

    pivot = self[0]

    # Use the comparator block when given (it returns -1/0/1), otherwise <=>.
    part  = self[1..-1].partition do |e|
      if block
        block.call(e, pivot) <= 0
      else
        (e <=> pivot) <= 0
      end
    end

    left  = part[0].sort(&block)
    right = part[1].sort(&block)

    left + [pivot] + right
  end


  # Sorts self. Comparisons for the sort will be done using the <=> operator
  # or using an optional code block. The block implements a comparison between
  # a and b, returning -1, 0, or +1.
  # See also Enumerable#sort_by.
  def sort!(&block)
    replace(sort(&block))
    self
  end


  # Returns self.
  # If called on a subclass of Array, converts the receiver to an Array object.
  def to_a
    return self
  end

  # lazy: a lazy enumerator over this array (Array does not include Enumerable here, so define directly).
  def lazy
    Enumerator::Lazy.new(self)
  end


  # Returns self.
  def to_ary
    return self
  end

  def to_yaml
    %s(puts "Array#to_yaml not implemented")
  end


  # Assumes that self is an array of arrays and transposes the rows and columns.
  # transpose -> swap rows and columns of an array of arrays. Each element is coerced via #to_ary
  # (TypeError otherwise); all rows must be the same length (IndexError otherwise). [] -> [].
  def transpose
    return [] if length == 0
    rows = []
    each do |row|
      if row.is_a?(Array)
        rows << row
      elsif row.respond_to?(:to_ary)
        rows << row.to_ary
      else
        raise TypeError.new("no implicit conversion of #{row.class} into Array")
      end
    end
    ncols = rows[0].length
    i = 0
    while i < rows.length
      if rows[i].length != ncols
        raise IndexError.new("element size differs (#{rows[i].length} should be #{ncols})")
      end
      i = i + 1
    end
    result = []
    c = 0
    while c < ncols
      col = []
      r = 0
      while r < rows.length
        col << rows[r][c]
        r = r + 1
      end
      result << col
      c = c + 1
    end
    result
  end

  # Returns a new array by removing duplicate values in self.
  def uniq
    uniq_arr = Array.new
    self.each do |item|
      if !uniq_arr.include?(item)
        uniq_arr << item
      end
    end
    uniq_arr
  end


  # Removes duplicate elements from self.
  # Returns nil if no changes are made (that is, no duplicates are found).
  def uniq!
    uniq_arr = self.uniq
    changes_made = uniq_arr.size != self.size
    self = self.uniq

    if changes_made
      return self
    else
      return nil
    end
  end


  # Prepends objects to the front of array. other elements up one.
  # Prepend the given objects to the front of self, returning self.
  def unshift(*objects)
    replace(objects + self)
    self
  end


  # Returns an array containing the elements in self corresponding to the given selector(s).
  # The selectors may be either integer indices or ranges.
  # See also Array#select.
  def values_at(*indices)
    result = []
    indices.each do |idx|
      if idx.is_a?(Range)
        a = idx.first
        b = idx.last
        a = a + length if a < 0
        b = b + length if b < 0
        b = b - 1 if idx.exclude_end?
        i = a
        while i <= b
          result << self[i]
          i = i + 1
        end
      else
        result << self[idx]
      end
    end
    result
  end


  def yaml_initialize
    %s(puts "Array#yaml_initialize not implemented")
  end

  # FIXME: Belongs in Enumerable
  # Converts any arguments to arrays, then merges elements of self with corresponding
  # elements from each argument. This generates a sequence of self.size n-element arrays,
  # where n is one more that the count of arguments. If the size of any argument is less
  # than enumObj.size, nil values are supplied. If a block given, it is invoked for each
  # output array, otherwise an array of arrays is returned.
  def zip(*args)
    # For now we fudge this, as it's only needed to handle a simple case of
    # an_array.zip(a_range) in the compiler itself. Though incidentally this is
    # one of the most painful things to handle, as since the argument is not an
    # Array, MRI converts all arguments to Enumerators.
    #
    # For now we handle both Array's and Range's the same, but can't enumerate over
    # anything else

    enums = args.collect{|a| a.to_enum}

    collect do |a|
      ary = [a]
      enums.each do |e|
        ary << e.next
      end
      ary
    end
  end


  # Set Union.
  # Returns a new array by joining this array with other_array, removing duplicates.
#  def |(other_array)
#    return (self + other_array).uniq
#  end
end
