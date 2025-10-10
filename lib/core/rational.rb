
class Rational
  def initialize(numerator, denominator)
    # FIXME: Requires gcd...

    @numerator = numerator
    @denominator = denominator
  end

  def denominator
    @denominator
  end

  def numerator
    @numerator
  end

  def to_s
    return "(#{numerator}/#{denominator})"
  end

  # FIXME: Verify
  def ==(other)
    if other.is_a?(Numeric)
      return @numerator == other.numerator and @denominator == other.denominator
    end
    return false
  end

  # Convert to Float for arithmetic operations
  def to_f
    @numerator.to_f / @denominator.to_f
  end

  # Convert to Integer (truncate)
  def to_i
    @numerator / @denominator
  end

  # to_int is called for type coercion (same as to_i for Rational)
  def to_int
    to_i
  end

  # Coerce method for arithmetic operations with other numeric types
  # When Integer calls Rational, Ruby will call rational.coerce(integer)
  # We return [float_version_of_rational, float_version_of_integer]
  def coerce(other)
    if other.is_a?(Integer)
      return [other.to_f, self.to_f]
    end
    [other, self]
  end
end

def Rational(numerator, denominator)
  Rational.new(numerator, denominator)
end
