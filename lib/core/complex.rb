
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

  # Squared magnitude a**2 + b**2 -- exact, unlike #abs which needs a square root.
  def abs2
    @real * @real + @imag * @imag
  end

  def rectangular
    [@real, @imag]
  end
  alias rect rectangular

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
end

# Ruby: Complex(real, imaginary = 0) -- the imaginary part is optional, so a 1-arg call must not raise
# ArgumentError (which crashed every complex spec whose fixtures build Complex(n) at load).
def Complex(a, b = 0)
  Complex.new(a, b)
end
