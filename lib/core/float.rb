
class Float
  # Stub constants - proper IEEE 754 values not implemented
  # IMPORTANT: Cannot use large literals during compilation - they cause overflow
  # Use computed values instead
  INFINITY = 1 << 28  # Large value without literal overflow
  MAX = (1 << 28) - 1
  # A true IEEE NaN is not representable while Float is stubbed; the CONSTANT
  # must exist though -- specs reference Float::NAN in before-blocks, and a
  # missing constant aborted whole files (kernel/sprintf, string/modulo).
  # NOTE: no 0.0 literals here -- the SELF-HOSTED compiler cannot compile
  # float literals yet (String#to_f is missing; MRI-hosted works, selftest-c
  # dies), which is also why INFINITY/MAX are integer expressions.
  NAN = Float.new
  EPSILON = Float.new
  MIN = Float.new
  DIG = 15
  MANT_DIG = 53

  # Reserve space for double value (8 bytes = 2 slots)
  # We use instance variables to ensure the compiler allocates space
  def initialize
    @value_low = 0
    @value_high = 0
  end

  def to_s
    # FIXME: Stub - proper float to string not implemented
    "0.0"
  end

  alias inspect to_s

  def to_i
    # Truncate toward zero (the ftoi primitive sets x87 RC=truncate around the store).
    %s(ftoi self)
  end

  alias to_int to_i

  def to_f
    self
  end

  def floor
    # FIXME: Stub - proper floor not implemented
    # Returns integer floor of float value
    to_i
  end

  def class
    Float
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

  # Predicate methods
  def nan?
    false
  end

  def infinite?
    nil
  end

  def finite?
    true
  end

  # FIXME: Stub for internal coercion - needed by comparison operators
  def __get_raw
    0
  end
end
