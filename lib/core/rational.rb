
# Rational: exact ratio of two integers, held in lowest terms with a positive denominator.
#
# The class is first declared (as a stub) in lib/core/numeric.rb so that it exists before Integer
# loads; this file reopens it and supplies the real arithmetic. Values are always normalised on
# construction: reduced by their gcd and with any sign carried on the numerator, so equal ratios have
# identical @numerator/@denominator (which is what == and hash rely on).
#
# Mixed Integer/Rational arithmetic is driven from Integer's operators: `2 + Rational(1,2)` promotes the
# Integer to Rational(2,1) and dispatches back here (see the Rational branches in lib/core/integer.rb).
class Rational < Numeric
  def initialize(numerator, denominator = 1)
    raise ZeroDivisionError.new("divided by 0") if denominator == 0
    # Carry the sign on the numerator so the denominator stays positive.
    if denominator < 0
      numerator = -numerator
      denominator = -denominator
    end
    g = numerator.abs.gcd(denominator)
    g = 1 if g == 0
    @numerator = numerator / g
    @denominator = denominator / g
  end

  def numerator
    @numerator
  end

  def denominator
    @denominator
  end

  def to_s
    "#{@numerator}/#{@denominator}"
  end

  def inspect
    "(#{@numerator}/#{@denominator})"
  end

  # Float value of the ratio.
  def to_f
    @numerator.to_f / @denominator.to_f
  end

  # Integer value, truncated toward zero (MRI semantics), unlike floor which rounds toward -infinity.
  def to_i
    q = @numerator.abs / @denominator
    @numerator < 0 ? -q : q
  end

  def to_int
    to_i
  end

  def to_r
    self
  end

  def hash
    [@numerator, @denominator].hash
  end

  # --- arithmetic -------------------------------------------------------------------------------------

  def +(other)
    if other.is_a?(Rational)
      Rational.new(@numerator * other.denominator + other.numerator * @denominator,
                   @denominator * other.denominator)
    elsif other.is_a?(Integer)
      Rational.new(@numerator + other * @denominator, @denominator)
    elsif other.is_a?(Float)
      to_f + other
    else
      __coerce_apply(other, :+)
    end
  end

  def -(other)
    if other.is_a?(Rational)
      Rational.new(@numerator * other.denominator - other.numerator * @denominator,
                   @denominator * other.denominator)
    elsif other.is_a?(Integer)
      Rational.new(@numerator - other * @denominator, @denominator)
    elsif other.is_a?(Float)
      to_f - other
    else
      __coerce_apply(other, :-)
    end
  end

  def *(other)
    if other.is_a?(Rational)
      Rational.new(@numerator * other.numerator, @denominator * other.denominator)
    elsif other.is_a?(Integer)
      Rational.new(@numerator * other, @denominator)
    elsif other.is_a?(Float)
      to_f * other
    else
      __coerce_apply(other, :*)
    end
  end

  def /(other)
    if other.is_a?(Rational)
      raise ZeroDivisionError.new("divided by 0") if other.numerator == 0
      Rational.new(@numerator * other.denominator, @denominator * other.numerator)
    elsif other.is_a?(Integer)
      raise ZeroDivisionError.new("divided by 0") if other == 0
      Rational.new(@numerator, @denominator * other)
    elsif other.is_a?(Float)
      to_f / other
    else
      __coerce_apply(other, :/)
    end
  end
  alias quo /

  def %(other)
    # A zero divisor -- Integer 0, Rational 0, or Float 0.0 -- is a ZeroDivisionError (MRI raises here
    # rather than letting a Float 0.0 divisor flow through to an Infinity/NaN result).
    raise ZeroDivisionError, "divided by 0" if other == 0
    q = (self / other).floor
    self - q * other
  end
  alias modulo %

  def remainder(other)
    q = (self / other).truncate
    self - q * other
  end

  def divmod(other)
    raise ZeroDivisionError, "divided by 0" if other == 0
    q = (self / other).floor
    [q, self - q * other]
  end

  def **(other)
    if other.is_a?(Integer)
      if other >= 0
        Rational.new(@numerator ** other, @denominator ** other)
      else
        n = -other
        raise ZeroDivisionError.new("divided by 0") if @numerator == 0
        # Inverting: a negative power flips numerator and denominator, then powers each.
        Rational.new(@denominator ** n, @numerator ** n)
      end
    else
      to_f ** other
    end
  end

  def -@
    Rational.new(-@numerator, @denominator)
  end

  def +@
    self
  end

  def abs
    Rational.new(@numerator.abs, @denominator)
  end

  # --- rounding ---------------------------------------------------------------------------------------

  # floor rounds toward -infinity; Integer#/ already floors so the ratio maps directly. With a non-zero
  # digit count MRI scales by 10**digits, applies the zero-arg rounding, and returns a Rational (positive
  # digits) or Integer (negative digits) -- see __scale_round.
  # The digit-precision argument to floor/ceil/truncate/round must be an Integer; MRI raises TypeError
  # "not an integer" for anything else (nil, a Float, a String, ...) and does NOT call #to_int on it.
  def __check_digits(digits)
    raise TypeError, "not an integer" unless digits.is_a?(Integer)
  end

  def floor(digits = 0)
    __check_digits(digits)
    return @numerator / @denominator if digits == 0
    __scale_round(digits, :floor)
  end

  # ceil rounds toward +infinity: ceil(n/d) == -floor(-n/d).
  def ceil(digits = 0)
    __check_digits(digits)
    return -((-@numerator) / @denominator) if digits == 0
    __scale_round(digits, :ceil)
  end

  def truncate(digits = 0)
    __check_digits(digits)
    return to_i if digits == 0
    __scale_round(digits, :truncate)
  end

  # round: nearest integer, halves away from zero (MRI default).
  def round(digits = 0)
    __check_digits(digits)
    if digits == 0
      d2 = 2 * @denominator
      return @numerator < 0 ? -((-@numerator * 2 + @denominator) / d2) : (@numerator * 2 + @denominator) / d2
    end
    __scale_round(digits, :round)
  end

  # Digit-precision rounding shared by floor/ceil/truncate/round. Positive digits: scale up by 10**digits,
  # apply the zero-arg rounding to land on an integer, then divide back down to a Rational. Negative
  # digits: scale down, round to an integer, and scale back up (an Integer result, as in MRI).
  def __scale_round(digits, op)
    if digits > 0
      m = 10 ** digits
      Rational.new((self * m).send(op), m)
    else
      m = 10 ** (-digits)
      (self / m).send(op) * m
    end
  end

  # --- comparison -------------------------------------------------------------------------------------

  # Cross-multiply for an exact comparison (denominators are positive so ordering is preserved). Returns
  # nil for incomparable operands, matching Numeric#<=>.
  def <=>(other)
    if other.is_a?(Rational)
      (@numerator * other.denominator) <=> (other.numerator * @denominator)
    elsif other.is_a?(Integer)
      @numerator <=> (other * @denominator)
    elsif other.is_a?(Float)
      to_f <=> other
    else
      nil
    end
  end

  def ==(other)
    if other.is_a?(Rational)
      @numerator == other.numerator && @denominator == other.denominator
    elsif other.is_a?(Integer)
      @denominator == 1 && @numerator == other
    elsif other.is_a?(Float)
      to_f == other
    else
      false
    end
  end

  # eql? is type-strict, unlike ==: (1/2r).eql?(0.5) is false (Float is not a Rational) and
  # (2/1r).eql?(2) is false (Integer), though both are ==. Without this, Rational inherits
  # Object#eql? (delegates to ==) and wrongly treats those as eql?. Rationals are normalised, so
  # value comparison of two Rationals via == is exact (1/2r eql? 2/4r is true).
  def eql?(other)
    return false if !other.is_a?(Rational)
    self == other
  end

  def <(other)
    __cmp(other) < 0
  end

  def <=(other)
    __cmp(other) <= 0
  end

  def >(other)
    __cmp(other) > 0
  end

  def >=(other)
    __cmp(other) >= 0
  end

  # --- predicates -------------------------------------------------------------------------------------

  def zero?
    @numerator == 0
  end

  def negative?
    @numerator < 0
  end

  def positive?
    @numerator > 0
  end

  def integer?
    false
  end

  def between?(min, max)
    self >= min && self <= max
  end

  # clamp(min, max) or clamp(range). Rational does not include Comparable, so provide it directly.
  def clamp(min, max = nil)
    if max.nil? && min.is_a?(Range)
      lo = min.begin
      hi = min.end
      return lo if !lo.nil? && self < lo
      return hi if !hi.nil? && self > hi
      return self
    end
    return min if self < min
    return max if self > max
    self
  end

  # Coerce an Integer or Float against this Rational. Integers promote to exact Rationals so mixed
  # arithmetic stays exact; Floats fall back to Float math.
  def coerce(other)
    if other.is_a?(Integer)
      [Rational.new(other, 1), self]
    elsif other.is_a?(Float)
      [other, to_f]
    else
      [other, self]
    end
  end

  # Shared guard for <,<=,>,>=: raise ArgumentError (as Comparable does) when the operands do not compare.
  def __cmp(other)
    c = (self <=> other)
    raise ArgumentError.new("comparison of Rational with #{other.inspect} failed") if c.nil?
    c
  end

  # Fallback for `Rational OP non-numeric`: use the other operand's coerce protocol.
  def __coerce_apply(other, op)
    if other.respond_to?(:coerce)
      a, b = other.coerce(self)
      a.send(op, b)
    else
      raise TypeError.new("#{other.class} can't be coerced into Rational")
    end
  end
end

# Kernel#Rational accepts more than two integers: a String argument ("3/4", "0.5") is parsed via
# String#to_r, and a Rational argument (in either position) is combined by division, so
# Rational("3/4") => (3/4), Rational("3", "4") => (3/4) and Rational(Rational(1,2), 3) => (1/6).
def Rational(numerator, denominator = 1)
  numerator = numerator.to_r if numerator.is_a?(String) || numerator.is_a?(Float)
  denominator = denominator.to_r if denominator.is_a?(String) || denominator.is_a?(Float)
  if numerator.is_a?(Rational) || denominator.is_a?(Rational)
    return numerator / denominator
  end
  Rational.new(numerator, denominator)
end
