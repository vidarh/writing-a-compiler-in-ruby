
class Float
  # Real IEEE-754 values now that float literals self-host and gas does decimal->IEEE at assemble
  # time. These finite literals assemble directly; INFINITY/NAN cannot (gas rejects an overflowing
  # literal, and there is no NaN literal syntax) so they are COMPUTED at the bottom of the class
  # body (1.0/0.0, 0.0/0.0), after Float#/ is defined.
  MAX = 1.7976931348623157e308
  MIN = 2.2250738585072014e-308
  EPSILON = 2.220446049250313e-16
  DIG = 15
  MANT_DIG = 53

  # Reserve space for double value (8 bytes = 2 slots)
  # We use instance variables to ensure the compiler allocates space
  def initialize
    @value_low = 0
    @value_high = 0
  end

  def to_s
    # The C helper __float_to_cstr (tgc.c) reads the raw double at offset 4 of self and writes a
    # NUL-terminated decimal (shortest round-trip via %g/strtod, or Infinity/-Infinity/NaN) into a
    # scratch buffer; __set_raw then wraps it into this String. `__array 16` = 64 bytes, ample.
    s = ""
    %s(let (buf)
      (assign buf (__array 16))
      (__float_to_cstr self buf)
      (callm s __set_raw (buf)))
    s
  end

  alias inspect to_s

  def to_i
    # Truncate toward zero (the ftoi primitive sets x87 RC=truncate around the store).
    %s(ftoi self)
  end

  alias to_int to_i

  # truncate (no ndigits) == to_i: toward zero.
  alias truncate to_i

  def to_f
    self
  end

  # floor/ceil/round return an Integer (no-arg form). to_i truncates toward zero, so:
  #   floor = t, or t-1 when self is negative and non-integer (self < t);
  #   ceil  = t, or t+1 when self is positive and non-integer (self > t).
  # round is half-away-from-zero: floor(self+0.5) for >=0, ceil(self-0.5) for <0.
  # (ndigits forms and the NaN/Infinity FloatDomainError are Phase 3.)
  def floor
    t = to_i
    self < t ? t - 1 : t
  end

  def ceil
    t = to_i
    self > t ? t + 1 : t
  end

  def round
    if self < 0.0
      (self - 0.5).ceil
    else
      (self + 0.5).floor
    end
  end

  def class
    Float
  end

  # Floats are immutable, so dup/clone return self. This ALSO avoids a crash: the generic
  # Object#dup copies instance variables, but a Float's raw 8-byte double (at offset 4) overlaps
  # the @value_low/@value_high ivar slots, so the default copy would treat the double's bytes as
  # object references and dereference garbage.
  def dup
    self
  end

  def clone(*)
    self
  end

  # Arithmetic. Non-Float operands are coerced to Float first (Integer#to_f, etc.), then the x87
  # primitive computes result = self <op> other into a freshly allocated Float. Divide-by-zero and
  # 0.0/0.0 produce IEEE Infinity/NaN for free from the FPU.
  def + other
    other = other.to_f unless other.is_a?(Float)
    r = Float.new
    %s(fadd self other r)
    r
  end

  def - other
    other = other.to_f unless other.is_a?(Float)
    r = Float.new
    %s(fsub self other r)
    r
  end

  def * other
    other = other.to_f unless other.is_a?(Float)
    r = Float.new
    %s(fmul self other r)
    r
  end

  def / other
    other = other.to_f unless other.is_a?(Float)
    r = Float.new
    %s(fdiv self other r)
    r
  end

  def ** other
    self
  end

  # Comparisons via x87 ordered compare (flt/fgt/feq return 0/1). NaN is unordered, so all three
  # yield 0 -> ==/< /> are false and <=> is nil against a NaN, matching MRI. Integer operands are
  # coerced to Float first.
  def == other
    other = other.to_f if other.is_a?(Integer)
    return false unless other.is_a?(Float)
    %s(if (feq self other) true false)
  end

  def eql? other
    # eql? is strict on type: 1.0.eql?(1) is false.
    return false unless other.is_a?(Float)
    %s(if (feq self other) true false)
  end

  def < other
    other = other.to_f unless other.is_a?(Float)
    %s(if (flt self other) true false)
  end

  def > other
    other = other.to_f unless other.is_a?(Float)
    %s(if (fgt self other) true false)
  end

  def <= other
    other = other.to_f unless other.is_a?(Float)
    r = false
    %s(if (flt self other) (assign r true))
    %s(if (feq self other) (assign r true))
    r
  end

  def >= other
    other = other.to_f unless other.is_a?(Float)
    r = false
    %s(if (fgt self other) (assign r true))
    %s(if (feq self other) (assign r true))
    r
  end

  def <=> other
    other = other.to_f if other.is_a?(Integer)
    return nil unless other.is_a?(Float)
    r = nil          # unordered (NaN on either side) stays nil
    # -1/0/1 must be TAGGED fixnums: a bare int in %s() is a raw machine word (raw 0 is a null
    # pointer -> crash when the caller treats the result as an object).
    %s(if (flt self other) (assign r (__int -1)))
    %s(if (fgt self other) (assign r (__int 1)))
    %s(if (feq self other) (assign r (__int 0)))
    r
  end

  def -@
    r = Float.new
    %s(fneg self r)
    r
  end

  def +@
    self
  end

  def abs
    r = Float.new
    %s(fabs self r)
    r
  end

  alias magnitude abs

  def zero?
    self == 0.0
  end

  # Predicate methods
  def nan?
    # NaN is the only value not equal to itself.
    r = true
    %s(if (feq self self) (assign r false))
    r
  end

  def infinite?
    # NOTE: use `0.0 - INFINITY` for -Inf, NOT the unary `-INFINITY` -- unary minus on a value
    # does not currently dispatch to Float#-@ in the parser, so it would compare against garbage.
    return 1 if self == INFINITY
    return -1 if self == (0.0 - INFINITY)
    nil
  end

  def finite?
    return false if nan?
    return false if infinite?
    true
  end

  # A simple hash over the two 32-bit halves of the raw double. Consistent with eql? for finite
  # values (the ±0.0 / NaN corners are not distinguished — acceptable for now).
  def hash
    lo = 0
    hi = 0
    %s(assign lo (__int (index self 1)))
    %s(assign hi (__int (index self 2)))
    lo ^ hi
  end

  # FIXME: Stub for internal coercion - needed by comparison operators
  def __get_raw
    0
  end

  # Real IEEE special values, computed via x87 division now that Float#/ is defined: 1.0/0.0 -> +Inf,
  # 0.0/0.0 -> NaN. (gas cannot assemble an overflowing/NaN literal, so these can't be plain literals.)
  INFINITY = 1.0 / 0.0
  NAN = 0.0 / 0.0
end
