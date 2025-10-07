
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
end

def Rational(numerator, denominator)
  Rational.new(numerator, denominator)
end
