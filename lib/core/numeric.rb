
class Numeric
  def dup
    self
  end

  # Numbers are immediates (or value objects): clone/dup return self. Object#clone's slot copy would
  # dereference the tagged fixnum and SIGSEGV, so override here.
  def clone(*args)
    self
  end

  def i
    Complex.new(0,self)
  end
end

# FIXME: Stub - Rational class needs full implementation
class Rational < Numeric
  def initialize(numerator, denominator=1)
    @numerator = numerator
    @denominator = denominator
  end

  def numerator
    @numerator
  end

  def denominator
    @denominator
  end

  def to_i
    @numerator / @denominator
  end

  def to_f
    @numerator.to_f / @denominator.to_f
  end

  def to_s
    "#{@numerator}/#{@denominator}"
  end
end
