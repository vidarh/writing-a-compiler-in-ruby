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

  # An Enumerator responds to #each, so it can be the source of a lazy pipeline. Defined here so every
  # Enumerator subclass (ArrayEnumerator, GenericEnumerator, ...) gets #lazy.
  def lazy
    Enumerator::Lazy.new(self)
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
