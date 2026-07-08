
# Complex: a number a + bi held as two components (@real, @imag). Only the exact operations that stay
# within the component types are implemented here -- addition, subtraction, multiplication, equality,
# conjugate, squared magnitude and formatting. Magnitude (#abs), argument and division need real square
# roots / trigonometry and so wait on Float; they are intentionally absent rather than wrong.
#
# Mixed `Integer op Complex` works without any change to Integer: Integer's operators fall through to the
# coerce protocol, and Complex#coerce promotes the Integer to Complex(n, 0) so `coerced[0] + coerced[1]`
# dispatches back here.
class Complex
  def initialize(real, imag = 0)
    @real = real
    @imag = imag
  end

  def real
    @real
  end

  def imag
    @imag
  end
  alias imaginary imag

  def +(other)
    if other.is_a?(Complex)
      Complex.new(@real + other.real, @imag + other.imag)
    elsif other.is_a?(Integer) || other.is_a?(Float) || other.is_a?(Rational)
      Complex.new(@real + other, @imag)
    else
      __coerce_apply(other, :+)
    end
  end

  def -(other)
    if other.is_a?(Complex)
      Complex.new(@real - other.real, @imag - other.imag)
    elsif other.is_a?(Integer) || other.is_a?(Float) || other.is_a?(Rational)
      Complex.new(@real - other, @imag)
    else
      __coerce_apply(other, :-)
    end
  end

  def *(other)
    if other.is_a?(Complex)
      # (a+bi)(c+di) = (ac - bd) + (ad + bc)i
      Complex.new(@real * other.real - @imag * other.imag,
                  @real * other.imag + @imag * other.real)
    elsif other.is_a?(Integer) || other.is_a?(Float) || other.is_a?(Rational)
      Complex.new(@real * other, @imag * other)
    else
      __coerce_apply(other, :*)
    end
  end

  # Division needs no square root: (a+bi)/(c+di) = (a+bi)(c-di) / (c**2 + d**2), and the denominator
  # abs2 is a real number. Components are divided with #quo so integer components yield exact Rationals
  # (matching MRI) while Float components stay Float.
  def /(other)
    if other.is_a?(Complex)
      d = other.abs2
      Complex.new((@real * other.real + @imag * other.imag).quo(d),
                  (@imag * other.real - @real * other.imag).quo(d))
    elsif other.is_a?(Integer) || other.is_a?(Float) || other.is_a?(Rational)
      Complex.new(@real.quo(other), @imag.quo(other))
    else
      __coerce_apply(other, :/)
    end
  end
  alias quo /

  def -@
    Complex.new(-@real, -@imag)
  end

  def +@
    self
  end

  def ==(other)
    if other.is_a?(Complex)
      @real == other.real && @imag == other.imag
    elsif other.is_a?(Integer) || other.is_a?(Float) || other.is_a?(Rational)
      @imag == 0 && @real == other
    else
      false
    end
  end

  def conjugate
    Complex.new(@real, -@imag)
  end
  alias conj conjugate

  # Squared magnitude a**2 + b**2 -- exact.
  def abs2
    @real * @real + @imag * @imag
  end

  # Magnitude sqrt(a**2 + b**2).
  def abs
    Math.sqrt(abs2)
  end
  alias magnitude abs

  def rectangular
    [@real, @imag]
  end
  alias rect rectangular

  # The argument (phase angle) measured from the positive real axis: atan2(imag, real).
  def arg
    Math.atan2(@imag, @real)
  end
  alias angle arg
  alias phase arg

  # Polar form: [magnitude, argument].
  def polar
    [abs, arg]
  end

  # Coerce a polar argument to a real Float: a real numeric converts; a Complex whose imaginary part is
  # zero uses its real part; anything else (nil, String, a non-real Complex) is a TypeError.
  def self.__polar_real(x)
    return x.to_f if x.is_a?(Integer) || x.is_a?(Float) || x.is_a?(Rational)
    if x.is_a?(Complex)
      return x.real.to_f if x.imag == 0
    end
    raise TypeError, "not a real value: #{x.nil? ? "nil" : x.class}"
  end

  # Build a Complex from a magnitude and angle: r*cos(theta) + r*sin(theta)*i (theta defaults to 0).
  def self.polar(r, theta = 0)
    rr = __polar_real(r)
    tt = __polar_real(theta)
    Complex(rr * Math.cos(tt), rr * Math.sin(tt))
  end

  def self.__real?(x)
    x.is_a?(Integer) || x.is_a?(Float) || x.is_a?(Rational)
  end

  # Build a Complex directly from its real and imaginary parts, which must be real numerics (a Complex,
  # nil, or String argument is a TypeError, unlike Complex() which is more permissive).
  def self.rectangular(real, imag = 0)
    unless __real?(real) && __real?(imag)
      raise TypeError, "not a real"
    end
    Complex.new(real, imag)
  end

  def self.rect(real, imag = 0)
    rectangular(real, imag)
  end

  # A Complex is never "real" in MRI, even when the imaginary part is zero.
  def real?
    false
  end

  def hash
    [@real, @imag].hash
  end

  def coerce(other)
    if other.is_a?(Complex)
      [other, self]
    else
      [Complex.new(other, 0), self]
    end
  end

  def to_s
    "#{@real}#{__imag_str}i"
  end

  def inspect
    "(#{@real}#{__imag_str}i)"
  end

  # Imaginary component with its leading sign, matching MRI's "+4"/"-4" formatting. A negative value
  # already carries its own "-", so only a non-negative one needs an explicit "+".
  def __imag_str
    @imag < 0 ? @imag.to_s : "+#{@imag}"
  end

  def __coerce_apply(other, op)
    if other.respond_to?(:coerce)
      a, b = other.coerce(self)
      a.send(op, b)
    else
      raise TypeError.new("#{other.class} can't be coerced into Complex")
    end
  end

  # The imaginary unit.
  I = Complex.new(0, 1)
end

# Ruby: Complex(real, imaginary = 0) -- the imaginary part is optional, so a 1-arg call must not raise
# ArgumentError (which crashed every complex spec whose fixtures build Complex(n) at load).
def Complex(a, b = 0)
  Complex.new(a, b)
end
