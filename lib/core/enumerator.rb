# FIXME
# This is all kinds of non-standard, but for
# now I only need very basic enumeration over
# Array and Range.
#


class Enumerator
  # Enumerator.new { |yielder| ... } stores the generator block; #each runs it with a Yielder that
  # forwards emitted values (y << v / y.yield v) to the each block. (Subclasses like ArrayEnumerator
  # override initialize/each and never call this.)
  def initialize(*args, &block)
    @gen_block = block
  end

  def size
    nil
  end

  def each(&outer)
    return self if !outer
    if @gen_block
      @gen_block.call(Enumerator::Yielder.new(outer))
    end
    self
  end

  def to_a
    r = []
    each { |x| r << x }
    r
  end

  # Enumerable-style methods over #each. Enumerator does not `include Enumerable` here (including it
  # segfaults -- see the Array note), so the common ones are defined directly, each driven by #each.
  def map
    r = []
    each { |x| r << yield(x) }
    r
  end
  def collect(&b); map(&b); end

  def flat_map
    r = []
    each do |x|
      v = yield(x)
      if v.is_a?(Array)
        v.each { |e| r << e }
      else
        r << v
      end
    end
    r
  end
  def collect_concat(&b); flat_map(&b); end

  def select
    r = []
    each { |x| r << x if yield(x) }
    r
  end
  def filter(&b); select(&b); end
  def find_all(&b); select(&b); end

  def reject
    r = []
    each { |x| r << x if !yield(x) }
    r
  end

  def find
    result = nil
    each { |x| if yield(x); result = x; break; end }
    result
  end
  def detect(&b); find(&b); end

  def each_with_index
    return to_enum(:each_with_index) if !block_given?
    i = 0
    each do |x|
      yield(x, i)
      i += 1
    end
    self
  end

  def with_index(offset = 0)
    return to_enum(:with_index, offset) if !block_given?
    i = offset
    each do |x|
      yield(x, i)
      i += 1
    end
    self
  end

  def each_with_object(memo)
    return to_enum(:each_with_object, memo) if !block_given?
    each { |x| yield(x, memo) }
    memo
  end
  def with_object(memo, &b)
    # Guard the no-block case here too: forwarding a nil &b into each_with_object would let its
    # `yield` fire against a nil block ("undefined method 'call' for nil"). Return an enumerator instead.
    return to_enum(:each_with_object, memo) if !block_given?
    each_with_object(memo, &b)
  end

  def include?(obj)
    found = false
    each { |x| if x == obj; found = true; break; end }
    found
  end
  def member?(obj); include?(obj); end

  def count
    n = 0
    each { |x| n += 1 }
    n
  end

  def first(n = nil)
    if n.nil?
      result = nil
      each { |x| result = x; break }
      return result
    end
    r = []
    each { |x| break if r.length >= n; r << x }
    r
  end

  def uniq
    seen = []
    each { |x| seen << x if !seen.include?(x) }
    seen
  end

  def reduce(init = nil)
    acc = init
    started = !init.nil?
    each do |x|
      if !started
        acc = x
        started = true
      else
        acc = yield(acc, x)
      end
    end
    acc
  end
  def inject(init = nil, &b); reduce(init, &b); end

  def sum(init = 0, &block)
    s = init
    each { |x| s = s + (block ? block.call(x) : x) }
    s
  end

  def filter_map(&block)
    return self if !block
    result = []
    each { |x| r = block.call(x); result << r if r }
    result
  end

  def cycle(n = nil, &block)
    return self if !block
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

  def minmax(&block)
    [min(&block), max(&block)]
  end

  def min
    m = nil
    started = false
    each do |x|
      if !started || x < m
        m = x
        started = true
      end
    end
    m
  end

  def max
    m = nil
    started = false
    each do |x|
      if !started || x > m
        m = x
        started = true
      end
    end
    m
  end

  def sort
    to_a.sort
  end

  def all?
    each { |x| return false if !yield(x) }
    true
  end

  def any?
    each { |x| return true if yield(x) }
    false
  end

  def none?
    each { |x| return false if yield(x) }
    true
  end

  def take(n)
    r = []
    each { |x| break if r.length >= n; r << x }
    r
  end

  def drop(n)
    r = []
    i = 0
    each do |x|
      r << x if i >= n
      i += 1
    end
    r
  end

  # An Enumerator responds to #each, so it can be the source of a lazy pipeline. Defined here so every
  # Enumerator subclass (ArrayEnumerator, GenericEnumerator, ...) gets #lazy.
  def lazy
    Enumerator::Lazy.new(self)
  end

  # Yielder: the object passed to a generator block; << and #yield emit a value to the consumer.
  class Yielder
    def initialize(consumer)
      @consumer = consumer
    end

    def yield(*args)
      @consumer.call(*args)
    end

    def <<(*args)
      @consumer.call(*args)
      self
    end
  end

  # Enumerator::Generator wraps a generator block; #each runs it with a Yielder. Enumerator.new already
  # covers the common case, but specs reference the class directly.
  class Generator
    def initialize(&block)
      @gen_block = block
    end

    def each(&outer)
      return self if !outer
      @gen_block.call(Enumerator::Yielder.new(outer)) if @gen_block
      self
    end
  end
end

class ArrayEnumerator < Enumerator
  def initialize(ary)
    @ary = ary
    @pos = 0
  end

  # Iterate the backing array. The base Enumerator#each drives a @gen_block that this subclass never sets,
  # so without this override #each (and everything built on it: to_a/map/sum/...) yielded nothing.
  def each(&block)
    return self if !block
    i = 0
    n = @ary.length
    while i < n
      block.call(@ary[i])
      i = i + 1
    end
    @ary
  end

  def size
    @ary.length
  end

  # External iteration: return successive elements, raising StopIteration past the end. (The previous
  # version incremented before reading, skipping index 0 and running one past the end.)
  def next
    raise StopIteration.new("iteration reached an end") if @pos >= @ary.length
    v = @ary[@pos]
    @pos = @pos + 1
    v
  end

  def peek
    raise StopIteration.new("iteration reached an end") if @pos >= @ary.length
    @ary[@pos]
  end

  def rewind
    @pos = 0
    self
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

class GenericEnumerator < Enumerator
  def initialize(receiver, gmethod = :each, *gargs)
    @receiver = receiver
    @gmethod = gmethod
    @gargs = gargs
  end
  def each(&block)
    return self if !block
    @receiver.__send__(@gmethod, *@gargs, &block)
  end
  def to_a
    r = []
    each { |*x| r << (x.length == 1 ? x[0] : x) }
    r
  end
end

# Lazy enumerator: chains transformations and evaluates only when forced (to_a / force / first). Early
# termination (take / first / take_while) breaks out of a possibly-infinite source via a LazyBreak
# exception (verified: raising inside a block unwinds through the source's each to an outer rescue). All
# steps accumulate into ONE Lazy over the ORIGINAL source (map/select/... return a new Lazy sharing @src),
# so there is never a Lazy nested inside another Lazy's each -- the single rescue in #each is correct.
class LazyBreak < StandardError
end

class Enumerator
  class Lazy < Enumerator
    def initialize(source, ops = nil)
      @src = source
      @ops = ops || []
    end

    def __step(op)
      Lazy.new(@src, @ops + [op])
    end

    def map(&b);            __step([:map, b]);        end
    def collect(&b);        __step([:map, b]);        end
    def flat_map(&b);       __step([:flat_map, b]);   end
    def collect_concat(&b); __step([:flat_map, b]);   end
    def select(&b);         __step([:select, b]);     end
    def filter(&b);         __step([:select, b]);     end
    def find_all(&b);       __step([:select, b]);     end
    def reject(&b);         __step([:reject, b]);     end
    def filter_map(&b);     __step([:filter_map, b]); end
    def take_while(&b);     __step([:take_while, b]); end
    def drop_while(&b);     __step([:drop_while, b]); end
    def take(n);            __step([:take, n]);       end
    def drop(n);            __step([:drop, n]);       end
    def lazy;               self;                      end

    # Evaluate the pipeline. The op blocks and `outer` are called INLINE inside the source's each block
    # (via a nested work-list loop), NEVER through a helper method -- a method invoked from within a block
    # that then calls procs triggers a closure/__env__ codegen bug, whereas direct inline proc calls work.
    # `vals` is the current work list (fan-out for flat_map); `st` holds per-op counters/flags for
    # take/drop/*_while. Early termination (take/take_while) raises LazyBreak to unwind out of the source.
    def each(&outer)
      return self if !outer
      ops = @ops
      nops = ops.length
      st = []
      i = 0
      while i < nops
        st[i] = 0
        i += 1
      end
      begin
        # A single block param (not |*a|): a splat block param resolves as a method call on self here
        # (a known splat-in-block-param codegen bug). Multi-value sources (Hash) thus yield their pair as
        # one value, which is acceptable -- lazy specs are overwhelmingly Array/Range.
        @src.each do |v|
          vals = [v]
          oi = 0
          while oi < nops
            op = ops[oi]
            t = op[0]
            nextvals = []
            vi = 0
            # NB: while loops, NOT vals.each { } -- a nested block inside this method mis-captures the
            # closure env; plain loops calling the procs directly are fine.
            while vi < vals.length
              x = vals[vi]
              if t == :map
                nextvals << op[1].call(x)
              elsif t == :select
                nextvals << x if op[1].call(x)
              elsif t == :reject
                nextvals << x if !op[1].call(x)
              elsif t == :filter_map
                fr = op[1].call(x)
                nextvals << fr if fr
              elsif t == :flat_map
                fr = op[1].call(x)
                if fr.is_a?(Array)
                  fi = 0
                  while fi < fr.length
                    nextvals << fr[fi]
                    fi += 1
                  end
                else
                  nextvals << fr
                end
              elsif t == :take_while
                if op[1].call(x)
                  nextvals << x
                else
                  raise LazyBreak.new
                end
              elsif t == :drop_while
                if st[oi] == 0 && op[1].call(x)
                  # still dropping the leading run
                else
                  st[oi] = 1
                  nextvals << x
                end
              elsif t == :take
                raise LazyBreak.new if st[oi] >= op[1]
                st[oi] += 1
                nextvals << x
              elsif t == :drop
                if st[oi] < op[1]
                  st[oi] += 1
                else
                  nextvals << x
                end
              end
              vi += 1
            end
            vals = nextvals
            oi += 1
          end
          k = 0
          while k < vals.length
            outer.call(vals[k])
            k += 1
          end
        end
      rescue LazyBreak
      end
      self
    end

    def to_a
      r = []
      each { |x| r << x }
      r
    end

    def force
      to_a
    end

    def first(n = nil)
      if n.nil?
        val = nil
        got = false
        each { |x| val = x; got = true; raise LazyBreak.new }
        return got ? val : nil
      end
      take(n).to_a
    end
  end
end
