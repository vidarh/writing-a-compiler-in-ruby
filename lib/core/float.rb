
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
  # IEEE-754 double parameters (base-2 and base-10 exponent ranges, radix), matching MRI.
  RADIX = 2
  MIN_EXP = -1021
  MAX_EXP = 1024
  MIN_10_EXP = -307
  MAX_10_EXP = 308

  # Reserve space for double value (8 bytes = 2 slots)
  # We use instance variables to ensure the compiler allocates space
  def initialize
    @value_low = 0
    @value_high = 0
  end

  # Format the double as "%.*e" (scientific, `prec+1` significant digits) via a DIRECT libc snprintf
  # call: the double is passed as its two 32-bit halves ((index self 1/2) = the words at offsets 4/8)
  # and the int precision through the variadic `*`. Returns e.g. "-1.234e+05".
  def __fmt_e(prec)
    buf = ""
    %s(let (b)
      (assign b (__array 20))
      (snprintf b 40 "%.*e" (sar prec) (index self 1) (index self 2))
      (callm buf __set_raw (b)))
    buf
  end

  def to_s
    return "NaN" if nan?
    inf = infinite?
    return "Infinity" if inf == 1
    return "-Infinity" if inf == -1
    # Shortest significant digits: the fewest %.*e that strtod-round-trips to this exact double.
    prec = 0
    s = ""
    while prec < 17
      s = __fmt_e(prec)
      break if s.to_f == self
      prec = prec + 1
    end
    __e_to_mri(s)
  end

  # Reconstruct MRI's to_s from a "%e" string "[-]d.ddde[+-]NN": fixed notation when the decimal
  # exponent is in [-4, 14] (decpt <= DBL_DIG), else "d.dddde[+-]NN" with a >=2-digit exponent.
  def __e_to_mri(s)
    neg = false
    i = 0
    if s[0, 1] == "-"
      neg = true
      i = 1
    end
    digits = s[i, 1]           # leading digit
    i = i + 1
    if s[i, 1] == "."          # "%.0e" has no decimal point (e.g. "1e+02"); skip it only if present
      i = i + 1
      while i < s.length && s[i, 1] != "e" && s[i, 1] != "E"
        digits = digits + s[i, 1]
        i = i + 1
      end
    end
    exp = s[(i + 1)..-1].to_i   # signed exponent
    nd = digits.length
    out = neg ? "-" : ""
    if exp >= -4 && exp <= 14
      if exp < 0
        out = out + "0."
        k = 0
        while k < (0 - exp - 1)
          out = out + "0"
          k = k + 1
        end
        out = out + digits
      else
        k = 0
        while k <= exp
          out = out + (k < nd ? digits[k, 1] : "0")
          k = k + 1
        end
        out = out + "."
        if exp + 1 < nd
          out = out + digits[(exp + 1)..-1]
        else
          out = out + "0"
        end
      end
    else
      out = out + digits[0, 1] + "."
      out = out + (nd > 1 ? digits[1..-1] : "0")
      out = out + "e"
      e2 = exp
      if e2 < 0
        out = out + "-"
        e2 = 0 - e2
      else
        out = out + "+"
      end
      es = e2.to_s
      es = "0" + es if es.length < 2
      out = out + es
    end
    out
  end

  alias inspect to_s

  # Format an INTEGER-valued double as its exact decimal integer string via a direct libc snprintf
  # ("%.0f"). The buffer is sized for the widest double (~309 integer digits + sign + NUL). Only
  # meaningful when self has no fractional part (e.g. the result of libm trunc); used by to_i for
  # magnitudes beyond the fixnum range, where the value must become a bignum.
  def __fmt_f0
    buf = ""
    %s(let (b)
      (assign b (__array 90))
      (snprintf b 350 "%.0f" (index self 1) (index self 2))
      (callm buf __set_raw (b)))
    buf
  end

  def to_i
    # NaN and +/-Infinity have no integer value (MRI raises FloatDomainError).
    raise FloatDomainError.new("NaN") if nan?
    inf = infinite?
    unless inf.nil?
      raise FloatDomainError.new(inf == 1 ? "Infinity" : "-Infinity")
    end
    # Beyond the fixnum range the result is a bignum: truncate toward zero with libm trunc (avoids the
    # floor/% recursion an in-Ruby truncation would cause) to an integer-valued double, then parse its
    # exact decimal string. Within range the x87 ftoi primitive truncates directly.
    if self >= 536870912.0 || self <= -536870912.0
      t = Float.new
      %s(do (trunc (index self 1) (index self 2)) (fstresult t))
      return t.__fmt_f0.to_i
    end
    %s(ftoi self)
  end

  alias to_int to_i

  # truncate toward zero. No-arg / ndigits == 0 -> Integer (via the ftoi primitive in to_i);
  # ndigits > 0 -> Float kept to that many decimals; ndigits < 0 -> Integer truncated to a power
  # of ten. Scale by 10**ndigits, truncate the integer part, scale back (same shape as floor/ceil).
  def truncate(ndigits = 0)
    return to_i if ndigits == 0
    if ndigits > 0
      f = 10.0 ** ndigits
      (self * f).truncate / f
    else
      f = 10 ** (-ndigits)
      (self / f).truncate * f
    end
  end

  def to_f
    self
  end

  # floor/ceil/round: no-arg (ndigits == 0) return an Integer. to_i truncates toward zero, so:
  #   floor = t, or t-1 when self is negative and non-integer (self < t);
  #   ceil  = t, or t+1 when self is positive and non-integer (self > t).
  # round is half-away-from-zero: floor(self+0.5) for >=0, ceil(self-0.5) for <0.
  # ndigits > 0 keeps that many decimals (Float result); ndigits < 0 rounds to a power of ten
  # (Integer). Both are done by scaling by 10**ndigits, applying the no-arg form, and scaling back.
  # (The NaN/Infinity FloatDomainError and round-half-to-even are still Phase 3.)
  def floor(ndigits = 0)
    if ndigits > 0
      f = 10.0 ** ndigits
      (self * f).floor / f
    elsif ndigits < 0
      f = 10 ** (-ndigits)
      (self / f).floor * f
    else
      t = to_i
      self < t ? t - 1 : t
    end
  end

  def ceil(ndigits = 0)
    if ndigits > 0
      f = 10.0 ** ndigits
      (self * f).ceil / f
    elsif ndigits < 0
      f = 10 ** (-ndigits)
      (self / f).ceil * f
    else
      t = to_i
      self > t ? t + 1 : t
    end
  end

  def round(ndigits = 0)
    if ndigits > 0
      f = 10.0 ** ndigits
      (self * f).round / f
    elsif ndigits < 0
      f = 10 ** (-ndigits)
      (self / f).round * f
    elsif self < 0.0
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

  # Return `other` as a Float when it is directly numeric (a Float as-is, an Integer via #to_f),
  # or nil when it is not -- the signal for the arithmetic operators to fall back to the coercion
  # protocol. (Every Float is truthy, including 0.0, so `if __as_float(x)` distinguishes cleanly.)
  def __as_float(other)
    return other if other.is_a?(Float)
    return other.to_f if other.is_a?(Integer)
    nil
  end

  # The coercion step shared by the arithmetic operators: an operand that cannot participate (does not
  # respond to #coerce) is a TypeError, matching MRI ("X can't be coerced into Float"), rather than the
  # NoMethodError a bare `other.coerce(self)` would raise. Otherwise return the [a, b] pair.
  def __coerce_pair(other)
    unless other.respond_to?(:coerce)
      raise TypeError, "#{other.class} can't be coerced into Float"
    end
    other.coerce(self)
  end

  # Coercion step for the ordered comparison operators (< > <= >=). Same as __coerce_pair, but a
  # non-coercible operand is an ArgumentError ("comparison of Float with X failed"), matching MRI's
  # relational-coerce path, rather than the TypeError arithmetic raises.
  def __coerce_relop(other)
    unless other.respond_to?(:coerce)
      raise ArgumentError, "comparison of Float with #{other.class} failed"
    end
    other.coerce(self)
  end

  # Arithmetic. A directly-numeric operand goes straight to the x87 primitive (result computed into a
  # freshly allocated Float; divide-by-zero / 0.0/0.0 yield IEEE Infinity/NaN for free). A non-numeric
  # operand follows MRI's coercion protocol: `other.coerce(self)` returns a [a, b] pair to which the
  # operator is re-applied, so a custom numeric type can participate and an exception raised inside
  # #coerce propagates instead of being swallowed.
  def + other
    o = __as_float(other)
    if o.nil?
      a, b = __coerce_pair(other)
      return a + b
    end
    r = Float.new
    %s(fadd self o r)
    r
  end

  def - other
    o = __as_float(other)
    if o.nil?
      a, b = __coerce_pair(other)
      return a - b
    end
    r = Float.new
    %s(fsub self o r)
    r
  end

  def * other
    o = __as_float(other)
    if o.nil?
      a, b = __coerce_pair(other)
      return a * b
    end
    r = Float.new
    %s(fmul self o r)
    r
  end

  def / other
    o = __as_float(other)
    if o.nil?
      a, b = __coerce_pair(other)
      return a / b
    end
    r = Float.new
    %s(fdiv self o r)
    r
  end

  def ** other
    # Integer exponent: exponentiation by squaring (O(log n), so a huge exponent overflows fast to
    # Infinity rather than looping). Negative -> reciprocal. A Float/Rational exponent needs libm pow,
    # which isn't wired yet, so it stays a stub for those.
    if other.is_a?(Integer)
      return 1.0 if other == 0
      n = other < 0 ? -other : other
      r = 1.0
      b = self
      while n > 0
        r = r * b if n % 2 == 1
        b = b * b
        n = n / 2
      end
      return 1.0 / r if other < 0
      r
    else
      self
    end
  end

  # Modulo (result takes the sign of the divisor) and remainder (sign of the dividend), per MRI.
  def % other
    o = __as_float(other)
    if o.nil?
      a, b = __coerce_pair(other)
      return a % b
    end
    # A zero divisor (Integer 0 or Float 0.0) raises ZeroDivisionError -- unlike Float#/, MRI's modulo
    # does not return NaN/Infinity for a zero divisor. (This also pre-empts floor() -> to_i raising
    # FloatDomainError on self/0.0 == Inf.)
    raise ZeroDivisionError.new("divided by 0") if o == 0.0
    # NaN operands or an infinite dividend give NaN.
    if nan? || o.nan? || infinite?
      return Float::NAN
    end
    # Modulo by +/-Infinity: the result keeps the divisor's sign. self already lies in the divisor's
    # half-open range when they share a sign (or self is zero), otherwise one wrap (self + other) lands
    # it there. (Without this, self/Inf == 0.0 and 0.0*Inf == NaN would poison the general formula.)
    if o.infinite?
      return self if self == 0.0 || (self < 0.0) == (o < 0.0)
      return self + o
    end
    self - (self / o).floor * o
  end

  alias modulo %

  def remainder other
    other = other.to_f unless other.is_a?(Float)
    self - (self / other).truncate * other
  end

  # Integer floored division and [quotient, modulo]. div returns an Integer; divmod's remainder takes
  # the sign of the divisor (matching Float#%).
  def div other
    o = __as_float(other)
    if o.nil?
      a, b = __coerce_pair(other)
      return a.div(b)
    end
    # Zero divisor raises ZeroDivisionError (Integer 0 or Float 0.0). A NaN/Infinite self falls through
    # to floor -> to_i, which raises FloatDomainError -- exactly what MRI's div/divmod do there.
    raise ZeroDivisionError.new("divided by 0") if o == 0.0
    (self / o).floor
  end

  def divmod other
    [div(other), self % other]
  end

  # quo/fdiv are exact float division; coerce implements the numeric coercion protocol.
  def quo other
    other = other.to_f unless other.is_a?(Float)
    self / other
  end

  def fdiv other
    other = other.to_f unless other.is_a?(Float)
    self / other
  end

  def coerce other
    [other.to_f, self]
  end

  def positive?
    self > 0.0
  end

  def negative?
    self < 0.0
  end

  # Comparisons via x87 ordered compare (flt/fgt/feq return 0/1). NaN is unordered, so all three
  # yield 0 -> ==/< /> are false and <=> is nil against a NaN, matching MRI. Integer operands are
  # coerced to Float first.
  def == other
    other = other.to_f if other.is_a?(Integer)
    if other.is_a?(Float)
      %s(if (feq self other) true false)
    else
      # Coercion failed (other is not numeric): defer to `other == self` so a type with a custom
      # `==` still gets a chance to match (MRI's Numeric#== fallback). Object#== is identity, so a
      # plain object returns false without looping.
      other == self
    end
  end

  def eql? other
    # eql? is strict on type: 1.0.eql?(1) is false.
    return false unless other.is_a?(Float)
    %s(if (feq self other) true false)
  end

  def < other
    o = __as_float(other)
    if o.nil?
      a, b = __coerce_relop(other)
      return a < b
    end
    %s(if (flt self o) true false)
  end

  def > other
    o = __as_float(other)
    if o.nil?
      a, b = __coerce_relop(other)
      return a > b
    end
    %s(if (fgt self o) true false)
  end

  def <= other
    o = __as_float(other)
    if o.nil?
      a, b = __coerce_relop(other)
      return a <= b
    end
    r = false
    %s(if (flt self o) (assign r true))
    %s(if (feq self o) (assign r true))
    r
  end

  def >= other
    o = __as_float(other)
    if o.nil?
      a, b = __coerce_relop(other)
      return a >= b
    end
    r = false
    %s(if (fgt self o) (assign r true))
    %s(if (feq self o) (assign r true))
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
