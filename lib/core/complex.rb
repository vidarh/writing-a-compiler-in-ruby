
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
    elsif __real_numeric?(other)
      Complex.new(@real + other, @imag)
    else
      __coerce_apply(other, :+)
    end
  end

  def -(other)
    if other.is_a?(Complex)
      Complex.new(@real - other.real, @imag - other.imag)
    elsif __real_numeric?(other)
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
    elsif __real_numeric?(other)
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
    elsif __real_numeric?(other)
      Complex.new(@real.quo(other), @imag.quo(other))
    else
      # MRI's Complex#/ (== #quo) coerces via :quo, not :/, so integer operands divide exactly to a
      # Rational (5 / 2 -> (5/2)) rather than truncating.
      __coerce_apply(other, :quo)
    end
  end
  alias quo /

  # Exponentiation. An Integer exponent is exact via repeated multiplication (negative -> reciprocal of
  # the positive power). A real (Float/Rational) exponent uses the polar form: z**w = |z|**w *
  # (cos(arg*w) + i*sin(arg*w)). A Complex exponent uses z**w = exp(w * log z), with log z = ln|z| +
  # i*arg z and exp(a+bi) = e**a * (cos b + i*sin b).
  def **(other)
    if other.is_a?(Integer)
      return Complex.new(1, 0) if other == 0
      if other > 0
        r = self
        n = other - 1
        while n > 0
          r = r * self
          n = n - 1
        end
        r
      else
        Complex.new(1, 0) / (self ** (0 - other))
      end
    elsif other.is_a?(Float) || other.is_a?(Rational)
      w = other.is_a?(Rational) ? other.to_f : other
      mag = abs ** w
      ang = arg * w
      Complex.new(mag * Math.cos(ang), mag * Math.sin(ang))
    elsif other.is_a?(Complex)
      p = other * Complex.new(Math.log(abs), arg)
      er = Math.exp(p.real)
      Complex.new(er * Math.cos(p.imag), er * Math.sin(p.imag))
    else
      __coerce_apply(other, :**)
    end
  end

  def -@
    Complex.new(-@real, -@imag)
  end

  def +@
    self
  end

  # Equality. Against another Complex, both components must be equal. Against a real numeric (a built-in
  # Integer/Float/Rational or a custom Numeric that answers #real? with true), self is equal iff its
  # imaginary part is zero and the real parts compare equal. Anything else -- a non-real Numeric or an
  # arbitrary object -- is handled by reflection: `other == self`, so the other side gets a chance to
  # define equality with a Complex.
  def ==(other)
    if other.is_a?(Complex)
      @real == other.real && @imag == other.imag
    elsif __real_numeric?(other)
      @imag == 0 && @real == other
    else
      other == self
    end
  end

  def __real_numeric?(other)
    return true if other.is_a?(Integer) || other.is_a?(Float) || other.is_a?(Rational)
    other.is_a?(Numeric) && other.real?
  end

  # eql? is stricter than ==: it never coerces, requires the other object to be a Complex, and requires
  # the corresponding parts to be of the SAME class (so Complex(1).eql?(Complex(1.0)) is false) as well
  # as == equal. It does not send #eql? to the parts -- class identity plus value equality suffice.
  def eql?(other)
    return false unless other.is_a?(Complex)
    return false unless @real.class == other.real.class && @imag.class == other.imag.class
    self == other
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
    return true if x.is_a?(Integer) || x.is_a?(Float) || x.is_a?(Rational)
    x.is_a?(Numeric) && x.real?
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

  def self.__part_finite?(x)
    return x.finite? if x.is_a?(Float)
    true   # Integer / Rational are always finite
  end

  def self.__part_infinite?(x)
    x.is_a?(Float) && !x.infinite?.nil?
  end

  # Finite iff BOTH components are finite; infinite? returns 1 if EITHER component is infinite, else nil.
  def finite?
    Complex.__part_finite?(@real) && Complex.__part_finite?(@imag)
  end

  def infinite?
    return 1 if Complex.__part_infinite?(@real) || Complex.__part_infinite?(@imag)
    nil
  end

  def to_c
    self
  end

  # A real conversion is only lossless when the imaginary part is an EXACT zero: an Integer or Rational
  # 0 (a Float 0.0 does NOT count), or a custom part whose #== 0 is true. Otherwise it is a RangeError.
  def __exact_zero_imag?
    !@imag.is_a?(Float) && @imag == 0
  end

  def to_i
    raise RangeError, "can't convert #{self} into Integer" unless __exact_zero_imag?
    @real.to_i
  end

  def to_f
    raise RangeError, "can't convert #{self} into Float" unless __exact_zero_imag?
    @real.to_f
  end

  # to_r accepts ANY zero imaginary part (including Float 0.0), unlike to_i/to_f which require an exact
  # zero -- Ruby 3.4 made Complex(x, 0.0).to_r return a Rational rather than raise.
  def to_r
    raise RangeError, "can't convert #{self} into Rational" unless @imag == 0
    @real.to_r
  end

  # denominator is the least common multiple of the two parts' denominators; numerator scales each
  # part up to that common denominator (so Complex(3/4, 3/4).numerator == Complex(3, 3), denominator 4).
  def denominator
    @real.denominator.lcm(@imag.denominator)
  end

  def numerator
    d = denominator
    Complex(@real.numerator * (d / @real.denominator), @imag.numerator * (d / @imag.denominator))
  end

  # Like to_r, but forwards to the real part's #rationalize (with the optional precision argument). The
  # imaginary part must be an EXACT zero, else RangeError; more than one argument is an ArgumentError.
  def rationalize(*args)
    if args.length > 1
      raise ArgumentError, "wrong number of arguments (given #{args.length}, expected 0..1)"
    end
    raise RangeError, "can't convert #{self} into Rational" unless __exact_zero_imag?
    @real.rationalize(*args)
  end

  # Complex is ordered only when BOTH operands are real (imaginary part an exact zero): then it compares
  # the real parts. Otherwise (an imaginary part on either side, or a non-numeric argument) it is nil.
  def <=>(other)
    return nil unless __exact_zero_imag?
    if other.is_a?(Complex)
      return nil unless other.__exact_zero_imag?
      @real <=> other.real
    elsif other.is_a?(Integer) || other.is_a?(Float) || other.is_a?(Rational)
      @real <=> other
    else
      nil
    end
  end

  def hash
    [@real, @imag].hash
  end

  def coerce(other)
    return [other, self] if other.is_a?(Complex)
    # The real numeric types wrap into Complex(other, 0). (Float is not a Numeric subclass in this
    # runtime, so it is checked explicitly alongside Integer/Rational.)
    if other.is_a?(Integer) || other.is_a?(Float) || other.is_a?(Rational)
      return [Complex.new(other, 0), self]
    end
    # A custom Numeric coerces only if it is real; a non-real Numeric or a non-numeric is a TypeError.
    if other.is_a?(Numeric) && other.real?
      return [Complex.new(other, 0), self]
    end
    raise TypeError, "#{other.class} can't be coerced into Complex"
  end

  def to_s
    "#{@real}#{__imag_str(@imag.to_s)}"
  end

  # inspect renders each part with #inspect (not #to_s), so a custom part's #inspect is honoured.
  def inspect
    "(#{@real.inspect}#{__imag_str(@imag.inspect)})"
  end

  # The imaginary component with its leading sign and trailing i, matching MRI. The sign is taken from
  # the value's own string form, so -0.0 -> "-0.0i" (not "+-0.0i"); a non-finite value (Infinity/NaN)
  # is written with a "*i" separator ("+Infinity*i") since "Infinityi" would be ambiguous.
  # Format the imaginary component from its already-rendered string `s` (its #to_s for Complex#to_s, its
  # #inspect for Complex#inspect). A leading "-" becomes the sign; otherwise "+". A "*" is inserted before
  # the trailing "i" whenever the magnitude does NOT end in a digit -- Infinity/NaN ("...y"/"...N") or a
  # bracketed custom rendering like "(2)" -- so "i" is never appended ambiguously to a letter or bracket.
  def __imag_str(s)
    if s[0..0] == "-"
      sign = "-"
      mag = s[1..-1]
    else
      sign = "+"
      mag = s
    end
    last = mag[-1..-1]
    suffix = __digit?(last) ? "i" : "*i"
    "#{sign}#{mag}#{suffix}"
  end

  def __digit?(c)
    c >= "0" && c <= "9"
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
