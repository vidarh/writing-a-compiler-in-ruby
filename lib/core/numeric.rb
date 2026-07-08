
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

  # Complex-view methods: a real number is its own real part with a zero imaginary part.
  def real
    self
  end

  def imaginary
    0
  end

  def imag
    0
  end

  def real?
    true
  end

  def to_c
    Complex.new(self, 0)
  end

  # The square of the absolute value. For a real number that is simply self*self (always >= 0 and
  # correct for negatives), and it is defined via #* so a custom numeric only needs to implement #*.
  def abs2
    self * self
  end

  def rectangular
    [self, 0]
  end

  def rect
    [self, 0]
  end
end

# Forward declaration so Rational exists before Integer loads (Integer's operators reference it). The
# real arithmetic, comparison and rounding are supplied when lib/core/rational.rb reopens the class.
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
