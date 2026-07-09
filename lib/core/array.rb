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
    # Forward the block (in __closure__) to initialize so `Array.new(n){|i| ...}` can fill via the block.
    %s(callm ob initialize ((splat __copysplat)) __closure__)
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
    # Argument handling uses RAW %s primitives (numargs + tag/shift on the raw slot), NOT Ruby method
    # calls on __copysplat: initialize runs for EVERY array creation including early bootstrap, where
    # __copysplat is not yet a usable Ruby Array and .length/&block break the self.new->initialize
    # calling convention (KNOWN_ISSUES #6). numargs==2 => no args (empty). numargs>=3 => first arg
    # present at (index __copysplat 0): a tagged Integer (low bit set) is a SIZE -> fill; a heap object
    # is a copy source -> __copy_init (existing behaviour). Fill/copy only run for explicit args, so the
    # bootstrap no-arg path is untouched.
    # The first raw slot IS the tagged fixnum size (a usable Ruby Integer), so pass it and the fill value
    # (2nd arg if numargs>3, else nil) straight to #__fill_n -- no raw shifts needed. The nil/index reads
    # here run only when a fixnum size was given, i.e. an explicit user Array.new(n) call, never bootstrap.
    %s(if (gt numargs 2)
      (if (ne (bitand (index __copysplat 0) 1) 0)
        (if (gt numargs 3)
          (callm self __fill_n ((index __copysplat 0) (index __copysplat 1)) __closure__)
          (callm self __fill_n ((index __copysplat 0) nil) __closure__))
        (callm self __copy_init ((index __copysplat 0)))))
    # Return self, not the raw result of the `if` above (which is a raw 0 when no args -> calling any
    # method on it, e.g. `ary.send(:initialize).should ...`, dereferences null and segfaults). MRI's
    # #initialize returns the receiver; `Array.new` ignores this (it uses `ob`), so it is safe.
    self
  end

  # Array.new(size) -> [nil]*size ; Array.new(size, val) -> [val]*size. `n` arrives as the tagged fixnum
  # size (an ordinary Ruby Integer here), so a plain Ruby fill loop works.
  def __fill_n n, val
    # MRI raises ArgumentError for an out-of-range size rather than trying to allocate it. Without this a
    # negative size silently produced []; a huge size (e.g. Array.new(fixnum_max+1)) looped __grow until
    # calloc failed and the write to a NULL buffer segfaulted (core/array/initialize_spec, new_spec). The
    # raise happens BEFORE any fill, so no allocation is attempted for an over-cap size. The cap (2^28) is
    # well above any realistic array yet below this compiler's larger fixnum range (so fixnum_max+1 =
    # 536870912, still a fixnum here, is rejected) and below where the fill would exhaust memory.
    raise ArgumentError.new("negative array size") if n < 0
    raise ArgumentError.new("array size too big") if n > 268435456
    i = 0
    if block_given?
      while i < n
        self << yield(i)
        i = i + 1
      end
    else
      while i < n
        self << val
        i = i + 1
      end
    end
    self
  end

  # Array.new(other_array) -> element-wise copy (valid MRI form). Plain Ruby:
  # unlike initialize's raw splat context, this is an ordinary method call, so
  # other.length/other[i] are safe. (The old __grow(other.__get_raw) called a
  # method Array never defined -- every Array.new(array)/subclass copy raised.)
  def __copy_init other
    if !other.is_a?(Array)
      if other.respond_to?(:to_ary)
        other = other.to_ary
      elsif other.respond_to?(:to_int)
        return __fill_n(other.to_int, nil)
      else
        raise TypeError, "no implicit conversion of #{other.class} into Integer"
      end
    end
    l = other.length
    i = 0
    while i < l
      self << other[i]
      i += 1
    end
    self
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
    return to_enum(:find) if !block_given?
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
    return to_enum(:reject) if !block_given?
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
    return to_enum(:select) if !block_given?
    a = self.class.new
    each do |item|
      if yield(item)
        a << item
      end
    end
    a
  end

  alias find_all select
  alias filter select

  # FIXME: Cut and paste from Enumerable
  def collect
    return to_enum(:collect) if !block_given?
    items = Array.new
    each do |item|
      items << yield(item)
    end
    items
  end

  alias map collect

  # Array#sum is defined directly here (Array cannot `include Enumerable` -- those methods segfault on
  # call; see the array-include-enumerable-broken note). NOTE: only non-yielding helpers are safe to add
  # this way -- a method that does `yield` inside an `each {}` block (min_by/group_by/each_with_object/
  # flat_map) currently segfaults on an Array (captured-yield-through-Array#each bug), though the same
  # code works on Set. So those are intentionally NOT added here yet.
  # See Enumerable#sum: plain #+ accumulation until a Float appears, then Kahan compensated summation for
  # MRI-precise float totals.
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


  # FIXME: Cut and paste from Enumerable
  def detect(ifnone = nil, &block)
    return to_enum(:detect) if !block
    self.each do |item|
      if block.call(item)
        return item
      end
    end
    if ifnone
      return ifnone.call
    end
    return nil
  end

  # grep / grep_v: select elements the pattern does (does not) match via `===`, optionally mapping each
  # kept element through a block. Array cannot `include Enumerable` in this runtime, so these mirror the
  # Enumerable definitions directly (both walk via #each, which Array provides).
  def grep(pattern, &block)
    out = []
    each do |x|
      if pattern === x
        out << (block ? block.call(x) : x)
      end
    end
    out
  end

  def grep_v(pattern, &block)
    out = []
    each do |x|
      if !(pattern === x)
        out << (block ? block.call(x) : x)
      end
    end
    out
  end

  # Like #each, but returns an Enumerator when called without a block (Array elements are single values,
  # so there is nothing to re-pack -- this just provides the method Enumerable would otherwise supply).
  def each_entry(&block)
    return to_enum(:each_entry) if !block
    each { |x| block.call(x) }
    self
  end

  # FIXME: Cut and paste from Enumerable
  def each_with_index(&block)
    return to_enum(:each_with_index) if !block_given?
    self.each_index do |i|
      block.call(self[i], i)
    end
    self
  end

  # each_cons / each_slice are defined directly on Array (which cannot `include Enumerable` here). Both
  # use index-based while loops with a top-level `yield` -- NOT a `yield` nested inside an `each {}` block,
  # which would hit the captured-yield-through-Array#each segfault (see the note near #sum). Block-less
  # calls return an Enumerator.
  def each_cons(n)
    return to_enum(:each_cons, n) if !block_given?
    i = 0
    len = length
    while i + n <= len
      window = []
      j = 0
      while j < n
        window << self[i + j]
        j += 1
      end
      yield window
      i += 1
    end
    nil
  end

  def each_slice(n)
    # A slice size of 0 never advances `i` -> infinite loop (negative runs it backwards); MRI raises.
    raise ArgumentError, "invalid slice size" if n <= 0
    return to_enum(:each_slice, n) if !block_given?
    i = 0
    len = length
    while i < len
      slice = []
      j = 0
      while j < n && i + j < len
        slice << self[i + j]
        j += 1
      end
      yield slice
      i += n
    end
    nil
  end

  # min_by / max_by / flat_map are Enumerable methods missing on Array (no `include Enumerable`). Like
  # each_cons/each_slice they use index-based while loops with a top-level yield (NOT yield inside an
  # each{} block, which segfaults on Array), so they are safe here.
  def min_by
    return to_enum(:min_by) if !block_given?
    return nil if length == 0
    best = self[0]
    best_v = yield(best)
    i = 1
    while i < length
      x = self[i]
      v = yield(x)
      if v < best_v
        best = x
        best_v = v
      end
      i += 1
    end
    best
  end

  def max_by
    return to_enum(:max_by) if !block_given?
    return nil if length == 0
    best = self[0]
    best_v = yield(best)
    i = 1
    while i < length
      x = self[i]
      v = yield(x)
      if v > best_v
        best = x
        best_v = v
      end
      i += 1
    end
    best
  end

  def flat_map
    return to_enum(:flat_map) if !block_given?
    result = []
    i = 0
    while i < length
      v = yield(self[i])
      if v.is_a?(Array)
        j = 0
        while j < v.length
          result << v[j]
          j += 1
        end
      else
        result << v
      end
      i += 1
    end
    result
  end
  alias collect_concat flat_map

  # Count occurrences of each distinct element (Array#tally). No block, no yield -- always safe.
  def tally
    counts = {}
    i = 0
    while i < length
      k = self[i]
      counts[k] = (counts[k] || 0) + 1
      i += 1
    end
    counts
  end


  # Repetition.
  # With a String argument (or something with #to_str), equivalent to self.join(str).
  # Otherwise the argument is coerced to an Integer and a new array is returned built
  # by concatenating that many copies of self.
  def *(amount)
    if amount.is_a?(String)
      return self.join(amount)
    end
    # String coercion takes priority over Integer coercion (MRI checks #to_str first).
    if !amount.is_a?(Integer) && amount.respond_to?(:to_str)
      return self.join(amount.to_str)
    end
    n = amount
    if !n.is_a?(Integer)
      if !n.respond_to?(:to_int)
        raise TypeError.new("no implicit conversion of #{amount.class} into Integer")
      end
      n = n.to_int
    end
    raise ArgumentError.new("negative argument") if n < 0
    result = []
    i = 0
    while i < n
      result.concat(self)
      i += 1
    end
    result
  end


  # Concatenation.
  # Returns a new array built by concatenating the two arrays together
  # to produce a third array.
  def +(other_array)
    added = self.dup
    added.concat(other_array)
    return added
  end

  # Set intersection: elements common to both arrays, no duplicates, self's order.
  # Membership via a Hash for O(n+m) (and Hash keying uses eql?, matching MRI).
  def &(other)
    other = __coerce_to_ary(other)
    seen = {}
    other.each { |x| seen[x] = true }
    out = []
    added = {}
    each do |x|
      if seen.key?(x) && !added.key?(x)
        added[x] = true
        out << x
      end
    end
    out
  end

  def intersection(*others)
    r = self.uniq
    others.each { |o| r = r & o }
    r
  end

  def intersect?(other)
    other = __coerce_to_ary(other)
    seen = {}
    other.each { |x| seen[x] = true }
    each do |x|
      return true if seen.key?(x)
    end
    false
  end

  # Set union: concatenation with duplicates removed, preserving first occurrence.
  def |(other)
    other = __coerce_to_ary(other)
    out = []
    added = {}
    each do |x|
      if !added.key?(x)
        added[x] = true
        out << x
      end
    end
    other.each do |x|
      if !added.key?(x)
        added[x] = true
        out << x
      end
    end
    out
  end

  def union(*others)
    r = self | []
    others.each { |o| r = r | o }
    r
  end

  def difference(*others)
    r = self
    others.each { |o| r = r - __coerce_to_ary(o) }
    r = r.dup if others.empty?
    r
  end

  # Coerce an argument to an Array via #to_ary (TypeError otherwise), like MRI's set ops.
  def __coerce_to_ary(other)
    return other if other.is_a?(Array)
    if other.respond_to?(:to_ary)
      r = other.to_ary
      return r if r.is_a?(Array)
    end
    raise TypeError, "no implicit conversion of #{other.class} into Array"
  end

  # Array of [key, value] pairs -> Hash (with an optional pair-mapping block).
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

  def self.try_convert(obj)
    return obj if obj.is_a?(Array)
    if obj.respond_to?(:to_ary)
      r = obj.to_ary
      return r if r.is_a?(Array) || r.nil?
      raise TypeError, "can't convert #{obj.class} to Array (#{obj.class}#to_ary gives #{r.class})"
    end
    nil
  end

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
    # NOTE: every array literal [...] compiles to Array.[] (see Compiler#compile_array),
    # so this is on the hottest bootstrap path -- it must stay EXACTLY on the
    # well-exercised self.new path. CONFIRMED 2026-07-05: bypassing a subclass's
    # #initialize per MRI via Class#__new SEGFAULTS the stage-1 compiler during
    # self-compilation BOTH unconditionally AND guarded to the subclass branch
    # (`if self.equal?(Array)` -- the guard never even fires self-hosted, so the
    # mere presence of the extra branch miscompiles: same layout-sensitive
    # family as the loop-carried-local bug in lib/core/glob.rb). Root-cause that
    # compiler bug before retrying; until then MyArray[...] with an incompatible
    # #initialize stays unsupported (~40 gated array specs).
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
     # Beginless (..e) / endless (b..) ranges: nil endpoints mean "from 0" / "to the end".
     start = 0 if start.nil?
     endless = xend.nil?
     xend = length - 1 if endless
     %s(assign start (__int (callm self __offset_to_pos(start))))
     %s(assign xend  (__int (callm self __offset_to_pos(xend))))

     if (start < 0)
       return Array.new
     end

     if xend < 0
       xend = length - 1
     end

     # For an exclusive range (1...3) stop one before the end index.
     if !endless && idx.exclude_end?
       xend = xend - 1
     end

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
  def [](idx, len = nil)
    # a[start, length] -> a subarray of at most `length` elements starting at `start`.
    if !len.nil?
      n = length
      s = idx < 0 ? n + idx : idx
      return nil if s < 0 || s > n || len < 0
      e = s + len
      e = n if e > n
      r = []
      i = s
      while i < e
        r << self[i]
        i = i + 1
      end
      return r
    end

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

  # slice(index) / slice(start, length) / slice(range) -- same selection as #[].
  def slice(*args)
    args.length == 1 ? self[args[0]] : self[args[0], args[1]]
  end

  # Like #slice but also removes the selected element(s) from self, returning what was removed.
  def slice!(*args)
    n = length
    if args.length == 1 && args[0].is_a?(Integer)
      i = args[0]
      i = n + i if i < 0
      return nil if i < 0 || i >= n
      return delete_at(i)
    end
    if args.length == 1 && args[0].is_a?(Range)
      r = args[0]
      s = r.begin
      s = 0 if s.nil?
      s = n + s if s < 0
      re = r.end
      if re.nil?
        # Endless range: remove everything from s
        e = n
      else
        # Normalize a negative end BEFORE the inclusive +1 (-1 means "last element")
        re = n + re if re < 0
        e = r.exclude_end? ? re : re + 1
      end
    else
      s = args[0]
      s = n + s if s < 0
      e = s + (args[1] || 0)
    end
    return nil if s < 0 || s > n
    e = n if e > n
    removed = self[s, e - s]
    # Rebuild self without the [s, e) span.
    rest = []
    i = 0
    while i < n
      rest << self[i] if i < s || i >= e
      i = i + 1
    end
    replace(rest)
    removed
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
    return to_enum(:delete_if) if !block_given?
    kept = []
    each {|x| kept << x if !yield(x) }
    replace(kept)
    self
  end

  # Keep only the elements for which the block is true (in place), returning self.
  def keep_if
    return to_enum(:keep_if) if !block_given?
    kept = []
    each { |x| kept << x if yield(x) }
    replace(kept)
    self
  end

  # First index of obj (==) or of the first element for which the block is true; nil if none.
  def find_index(*args, &block)
    return to_enum(:find_index) if !block && args.empty?
    i = 0
    n = length
    if block
      while i < n
        return i if block.call(self[i])
        i = i + 1
      end
    else
      obj = args[0]
      while i < n
        return i if self[i] == obj
        i = i + 1
      end
    end
    nil
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
    # Re-read self.size on every iteration (not a cached snapshot): MRI's Array#each observes elements
    # appended to the array DURING iteration, and stops early if it shrinks. A cached length missed
    # both (array/{all,none,count,each,...} "tolerates increasing an array size during iteration").
    if a == 1
      while i < self.size
        el = self[i]
        yield(el)
        i += 1
      end
      return self
    end

    while i < self.size
      el = self[i]
      if el.is_a?(Array)
        yield(*el)
      else
        yield(el)
      end
      i += 1
    end
    self
  end


  alias member? include?


  # Same as Array#each, but passes the index of the element
  # instead of the element itself.
  def each_index
    return to_enum(:each_index) { self.size } if !block_given?
    i = 0
    while i < self.size
      yield(i)
      i += 1
    end
    self
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

    # Recursion guard for cyclic (self-referential) arrays, mirroring Array#==: without it, mutually
    # recursive structures (a=[b]; b=[a]) descend forever -> stack overflow / SIGSEGV. Use a flag
    # distinct from =='s @__comparing so the two never clobber each other. Accumulate into `result`
    # and clear the flag at the end rather than early-returning, otherwise a false result would leave
    # @__eql_comparing set for the next comparison.
    return true if @__eql_comparing
    @__eql_comparing = true
    result = true
    i = 0
    l = self.length
    while i < l
      # eql? is element-wise #eql?, NOT ==: [1].eql?([1.0]) is false even though [1] == [1.0].
      result = false if !self[i].eql?(other_array[i])
      i += 1
    end
    @__eql_comparing = false
    result
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
      # A negative start index counts from the end; if it is still negative after adding the length it
      # points before the start of the array, so clamp to 0 (MRI). Without this, `[1,2,3].fill('a',-25,3)`
      # left s negative and the growing `self[s] = ...` below raised "index too small" instead of filling
      # from index 0.
      s = 0 if s < 0
      e = spec1.nil? ? n : s + spec1
    end
    # Same out-of-range guard as __fill_n (Array.new): MRI raises rather than attempt an absurd
    # allocation. Without this, `fill(10, 1, fixnum_max)` ground through 2^30 growing element
    # writes until the process was OOM-killed (array/fill_spec hung there).
    raise ArgumentError.new("array size too big") if e > 268435456
    i = s
    while i < e
      self[i] = block ? block.call(i) : obj
      i = i + 1
    end
    self
  end

  # First n elements / all but the first n elements.
  def take(n)
    raise ArgumentError.new("attempt to take negative size") if n < 0
    self[0, n] || []
  end

  def drop(n)
    raise ArgumentError.new("attempt to drop negative size") if n < 0
    n >= length ? [] : self[n, length - n]
  end

  # Elements from the front while the block is true.
  def take_while
    return to_enum(:take_while) if !block_given?
    result = []
    each do |x|
      break if !yield(x)
      result << x
    end
    result
  end

  # Elements after the leading run for which the block is true.
  def drop_while
    return to_enum(:drop_while) if !block_given?
    result = []
    dropping = true
    each do |x|
      dropping = false if dropping && !yield(x)
      result << x if !dropping
    end
    result
  end

  # reduce / inject: combine elements. Forms: reduce(sym), reduce(init, sym), reduce(init){blk},
  # reduce{blk}. Enumerable methods missing on Array; index-based loop with a top-level block.call /
  # send (no yield inside an each{} block), so safe here.
  def reduce(*args, &block)
    if block
      if args.length > 0
        memo = args[0]
        i = 0
      else
        return nil if length == 0
        memo = self[0]
        i = 1
      end
      while i < length
        memo = block.call(memo, self[i])
        i += 1
      end
      memo
    else
      # Symbol form: reduce(:+) or reduce(init, :+)
      if args.length >= 2
        memo = args[0]
        sym = args[1]
        i = 0
      else
        return nil if length == 0
        memo = self[0]
        sym = args[0]
        i = 1
      end
      while i < length
        memo = memo.send(sym, self[i])
        i += 1
      end
      memo
    end
  end
  alias inject reduce

  # Yield each element with the memo object, returning memo (Array#each_with_object).
  def each_with_object(memo)
    return to_enum(:each_with_object, memo) if !block_given?
    i = 0
    while i < length
      yield self[i], memo
      i += 1
    end
    memo
  end

  # Group elements by the block's return value into a Hash of value => [elements].
  def group_by
    return to_enum(:group_by) if !block_given?
    h = {}
    i = 0
    while i < length
      x = self[i]
      k = yield(x)
      # NB: explicit nil-check rather than `h[k] ||= []` -- op-assign on a hash index with a boolean
      # literal key (h[true] ||= ...) currently miscompiles ("undefined method 'true'").
      arr = h[k]
      if arr.nil?
        arr = []
        h[k] = arr
      end
      arr << x
      i += 1
    end
    h
  end

  # Split into runs, breaking between adjacent elements where the block(prev, cur) is false.
  def chunk_while(&block)
    return to_enum(:chunk_while) if !block_given?
    result = []
    return result if length == 0
    run = [self[0]]
    i = 1
    while i < length
      if block.call(self[i - 1], self[i])
        run << self[i]
      else
        result << run
        run = [self[i]]
      end
      i += 1
    end
    result << run
    result
  end

  # slice_when: inverse split of chunk_while -- start a new run whenever block(prev, cur) is true.
  def slice_when(&block)
    return to_enum(:slice_when) if !block_given?
    result = []
    return result if length == 0
    run = [self[0]]
    i = 1
    while i < length
      if block.call(self[i - 1], self[i])
        result << run
        run = [self[i]]
      else
        run << self[i]
      end
      i += 1
    end
    result << run
    result
  end

  # chunk: group consecutive elements with the same block value into [key, [elements...]] pairs.
  def chunk
    return to_enum(:chunk) if !block_given?
    result = []
    return result if length == 0
    key = yield(self[0])
    run = [self[0]]
    i = 1
    while i < length
      k = yield(self[i])
      if k == key
        run << self[i]
      else
        result << [key, run]
        key = k
        run = [self[i]]
      end
      i += 1
    end
    result << [key, run]
    result
  end

  # filter_map: map, keeping only truthy results (map + compact-of-falsy).
  def filter_map
    return to_enum(:filter_map) if !block_given?
    result = []
    i = 0
    while i < length
      v = yield(self[i])
      result << v if v
      i += 1
    end
    result
  end

  # one?: true iff exactly one element is truthy (or matches the block).
  def one?
    n = 0
    i = 0
    while i < length
      x = self[i]
      match = block_given? ? yield(x) : x
      if match
        n += 1
        return false if n > 1
      end
      i += 1
    end
    n == 1
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
  # max / max(n) / max{|a,b| } / max(n){|a,b| }. With an integer n, returns the n greatest elements in
  # descending order (an Array); otherwise the single greatest. An optional block is a two-arg comparator.
  def max(n = nil, &block)
    return __extreme_n(n, true, &block) if !n.nil?
    return nil if self.empty?

    max_val = self[0]
    i = 1
    s = self.size

    while i < s
      el = self[i]
      c = block ? block.call(el, max_val) : (el <=> max_val)
      max_val = el if c > 0
      i += 1
    end

    max_val
  end

  # min / min(n) / min{|a,b| } / min(n){|a,b| }. With n, returns the n smallest elements ascending.
  def min(n = nil, &block)
    return __extreme_n(n, false, &block) if !n.nil?
    return nil if self.empty?

    min_val = self[0]
    i = 1
    s = self.size

    while i < s
      el = self[i]
      c = block ? block.call(el, min_val) : (el <=> min_val)
      min_val = el if c < 0
      i += 1
    end

    min_val
  end

  # Shared n-element extremum: sort (by the optional comparator block) ascending, reverse for the max
  # side, and take the first n. n may exceed the length (returns all) but must not be negative.
  def __extreme_n(n, descending, &block)
    raise ArgumentError.new("negative size (#{n})") if n < 0
    sorted = block ? sort {|a, b| block.call(a, b) } : sort {|a, b| a <=> b }
    sorted = sorted.reverse if descending
    sorted[0, n]
  end

  # [min, max].
  def minmax
    [min, max]
  end

  # [min_by(&block), max_by(&block)] in one pass' worth of API (two here). Block-less yields an Enumerator.
  def minmax_by(&block)
    return to_enum(:minmax_by) if !block
    [min_by(&block), max_by(&block)]
  end

  # Enumerable#entries is a synonym for #to_a.
  def entries
    to_a
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
    # An intermediate element must respond to #dig to keep traversing; MRI raises TypeError (not
    # NoMethodError) otherwise, e.g. dig'ing past a leaf Integer.
    raise TypeError, "#{v.class} does not have #dig method" if !v.respond_to?(:dig)
    v.dig(*rest)
  end

  # Binary search over a sorted array. find-minimum mode: block returns true/false, returns the first
  # element for which it is true. find-any mode: block returns a number, returns an element for which it
  # is 0 (narrowing on the sign). Returns nil if nothing matches. The array must be sorted for the mode.
  def bsearch(&block)
    return to_enum(:bsearch) if !block
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
      elsif r.is_a?(Integer)
        # find-any mode: 0 means match, <0 search left, >0 search right.
        if r == 0
          return v
        elsif r > 0
          lo = mid + 1
        else
          hi = mid
        end
      else
        raise TypeError.new("wrong argument type #{r.class} (must be numeric, true, false or nil)")
      end
    end
    found
  end

  # All n-element combinations (order within the array preserved, no repeats). With a block, yields each
  # and returns self; without a block returns the array of combinations (answers .to_a/.each like MRI's
  # Enumerator for the common use).
  def combination(n, &block)
    return to_enum(:combination, n) { __combination_size(n) } if !block
    result = []
    if n >= 0 && n <= length
      __combination_into(n, 0, [], result)
    end
    result.each { |c| block.call(c) }
    self
  end

  # Binomial coefficient C(m, k), 0 when k is out of [0, m]. Uses the smaller of k / m-k for fewer
  # iterations, and multiplies-before-dividing so every intermediate stays an exact integer.
  def __binomial(m, k)
    return 0 if k < 0 || k > m
    k = m - k if k > m - k
    r = 1
    i = 0
    while i < k
      r = r * (m - i) / (i + 1)
      i += 1
    end
    r
  end

  # Number of n-combinations of self: C(length, n), or 0 when n is out of [0, length].
  def __combination_size(n)
    __binomial(length, n)
  end

  # Number of n-repeated-combinations of self: the multiset coefficient C(length + n - 1, n).
  def __rep_comb_size(n)
    return 0 if n < 0
    return 1 if n == 0
    return 0 if length == 0
    __binomial(length + n - 1, n)
  end

  # All n-length permutations (n defaults to the array length). Block form yields each and returns self.
  def permutation(n = nil, &block)
    len = length
    n = len if n.nil?
    result = []
    if n >= 0 && n <= len
      used = []
      i = 0
      while i < len
        used << false
        i = i + 1
      end
      __permutation_into(n, [], used, result)
    end
    if block
      result.each { |p| block.call(p) }
      self
    else
      result
    end
  end

  def __permutation_into(n, current, used, result)
    if current.length == n
      result << current.dup
      return
    end
    i = 0
    while i < length
      if !used[i]
        used[i] = true
        current << self[i]
        __permutation_into(n, current, used, result)
        current.pop
        used[i] = false
      end
      i = i + 1
    end
  end

  # All n-length sequences drawn from self WITH repetition.
  def repeated_permutation(n, &block)
    # Coerce the length to an Integer (MRI truncates Float args toward zero). Without this a Float n
    # never satisfies the `current.length == n` base case -> infinite recursion / stack overflow.
    n = n.to_int unless n.is_a?(Integer)
    result = []
    __repeated_perm_into(n, [], result) if n >= 0
    if block
      result.each { |p| block.call(p) }
      self
    else
      result
    end
  end

  def __repeated_perm_into(n, current, result)
    if current.length == n
      result << current.dup
      return
    end
    i = 0
    while i < length
      current << self[i]
      __repeated_perm_into(n, current, result)
      current.pop
      i = i + 1
    end
  end

  # All n-length non-decreasing-index combinations drawn from self WITH repetition.
  def repeated_combination(n, &block)
    return to_enum(:repeated_combination, n) { __rep_comb_size(n) } if !block
    result = []
    __repeated_comb_into(n, 0, [], result) if n >= 0
    result.each { |c| block.call(c) }
    self
  end

  def __repeated_comb_into(n, start, current, result)
    if current.length == n
      result << current.dup
      return
    end
    i = start
    while i < length
      current << self[i]
      __repeated_comb_into(n, i, current, result)
      current.pop
      i = i + 1
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
    arrays = [self]
    others.each { |o| arrays << o }
    # Guard against an unreasonably large result: the number of tuples is the product of the lengths, which
    # for `a.product(a, a, ...)` can be ~1e22 -> building them all is an OOM/hang. MRI raises RangeError
    # when that count would overflow a long. Any empty input array makes the whole product empty.
    total = 1
    arrays.each do |arr|
      n = arr.length
      return [] if n == 0
      raise RangeError, "product result is too large" if total > (0x7fffffff / n)
      total = total * n
    end
    result = [[]]
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
    # Pattern copied from String#hash.
    #
    # Recursion guard: a self-referential array (rec = []; rec << rec) would
    # otherwise recurse forever through the `c.hash` call below and segfault.
    # When we re-enter #hash on an array already being hashed, contribute a
    # fixed constant for the cyclic back-edge instead (mirrors the @__comparing
    # guard in #<=>), so the result terminates and is stable for equal cycles.
    return 8675309 if @__hashing
    @__hashing = true
    %s(assign h 5381)
    %s(assign h (add (mul h 33) (callm self length)))
    each do |c|
      %s(assign h (add (mul h 33) (callm c hash)))
    end
    @__hashing = nil
    %s(__int h)
  end


  # Returns the index of the first object in self such that is == to obj.
  # Returns nil if no match is found.
  def index(obj = nil, &block)
    i = 0
    l = length
    # Block form: index of the first element for which the block is true.
    if obj.nil? && block
      while (i < l)
        if yield(self[i])
          return i
        end
        i+=1
      end
      return nil
    end
    while (i < l)
      if self[i] == obj
        return i
      end
      i+=1
    end
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
  def join(sep = nil)
    sep = sep.to_s
    __join(sep, [])
  end

  # Recursive worker for #join: nested arrays are joined with the same separator
  # and spliced in (so [1,[2,3]].join(":") == "1:2:3"). A leading empty string
  # element must still be followed by a separator, so track "first" explicitly
  # rather than testing whether the accumulator is empty. `seen` holds the arrays
  # on the current path (by identity) so a self-referential array raises rather
  # than recursing forever, matching MRI.
  def __join(sep, seen)
    seen.each do |s|
      raise ArgumentError.new("recursive array join") if s.equal?(self)
    end
    inner = seen + [self]
    join_str = ""
    first = true
    self.each do |item|
      join_str << sep if !first
      first = false
      if item.is_a?(Array)
        join_str << item.__join(sep, inner)
      else
        join_str << item.to_s
      end
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


  # Invokes the block once for each element of self, replacing the element
  # with the value returned by the block (in place). Returns self.
  def collect!
    i = 0
    n = self.size
    while i < n
      self[i] = yield(self[i])
      i += 1
    end
    self
  end


  # Invokes the block once for each element of self, replacing the element
  # with the value returned by the block (in place). Returns self.
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


  # Array#pack: delegates to the shared __Pack codec (lib/core/pack.rb).
  # Integer directives (C c S s L l Q q N n V v J j I i w U), string directives
  # (a A Z b B h H m u) and position directives (x X @) with <>/!/_ modifiers.
  # Float directives raise NotImplementedError until Float lands.
  def pack(fmt)
    if !fmt.is_a?(String)
      raise TypeError, "no implicit conversion of #{fmt.class} into String" if !fmt.respond_to?(:to_str)
      fmt = fmt.to_str
    end
    __Pack.pack(self, fmt)
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
    # Frozen check up front so even push() with no arguments raises, per MRI. Checked here rather
    # than in the hot #<< path (every internal array append) since push raises before reaching it.
    raise FrozenError.new("can't modify frozen Array: #{inspect}") if frozen?
    i = 0
    n = objects.length
    while i < n
      self << objects[i]
      i = i + 1
    end
    self
  end
  alias append push


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
    return to_enum(:partition) if !block
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
    return to_enum(:sort_by) if !block
    return self if length <= 1
    pivot_el = self[0]
    pivot = block.call(pivot_el)
    part  = self[1..-1].partition {|e| block.call(e) < pivot }

    left  = part[0].sort_by(&block)
    right = part[1].sort_by(&block)

    left + [pivot_el] + right
  end

  # In-place sort_by (returns self).
  def sort_by!(&block)
    return to_enum(:sort_by!) if !block
    replace(sort_by(&block))
    self
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
    # zip only ever needs the first `length` elements of each argument, so take exactly that many rather
    # than materialising the whole thing: `[1,2].zip(10.upto(Float::INFINITY))` must not try to realise an
    # infinite (or huge) enumerable via to_a -> hang. Array args index directly; others take first(length)
    # (lazy for a proper enumerator). Shorter arguments are padded with nil in the lockstep loop below.
    others = args.collect { |a| a.is_a?(Array) ? a : a.first(length) }
    result = block_given? ? nil : []
    i = 0
    n = length
    while i < n
      row = [self[i]]
      others.each do |o|
        row << (i < o.length ? o[i] : nil)
      end
      if block_given?
        yield row
      else
        result << row
      end
      i += 1
    end
    result
  end


end
