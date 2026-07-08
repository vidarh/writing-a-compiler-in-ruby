# Math module. Each function calls the corresponding libc math.h function DIRECTLY (the double
# argument is passed as its two 32-bit halves; the double result comes back in FPU st0 and is
# captured with fstresult). Domain errors that MRI raises as Math::DomainError are checked here.

module Math
  class DomainError < StandardError
  end

  PI = 3.141592653589793
  E = 2.718281828459045

  # Coerce an argument to Float the way MRI's Math functions do: a real numeric converts, but a String
  # or nil (and anything without #to_f) is a TypeError -- unlike a plain `x.to_f`, which would silently
  # turn "test" into 0.0.
  def self.__coerce(x)
    return x if x.is_a?(Float)
    return x.to_f if x.is_a?(Integer) || x.is_a?(Rational)
    if x.nil? || x.is_a?(String) || !x.respond_to?(:to_f)
      raise TypeError, "can't convert #{x.nil? ? "nil" : x.class} into Float"
    end
    x.to_f
  end

  def self.sqrt(x)
    x = __coerce(x)
    raise DomainError, "Numerical argument is out of domain - \"sqrt\"" if x < 0.0
    r = Float.new
    %s(do (sqrt (index x 1) (index x 2)) (fstresult r))
    r
  end

  def self.cbrt(x)
    x = __coerce(x)
    r = Float.new
    %s(do (cbrt (index x 1) (index x 2)) (fstresult r))
    r
  end

  def self.exp(x)
    x = __coerce(x)
    r = Float.new
    %s(do (exp (index x 1) (index x 2)) (fstresult r))
    r
  end

  def self.log(x, base = nil)
    x = __coerce(x)
    raise DomainError, "Numerical argument is out of domain - \"log\"" if x < 0.0
    r = Float.new
    %s(do (log (index x 1) (index x 2)) (fstresult r))
    return r if base.nil?
    r / log(base)
  end

  def self.log2(x)
    x = __coerce(x)
    raise DomainError, "Numerical argument is out of domain - \"log2\"" if x < 0.0
    r = Float.new
    %s(do (log2 (index x 1) (index x 2)) (fstresult r))
    r
  end

  def self.log10(x)
    x = __coerce(x)
    raise DomainError, "Numerical argument is out of domain - \"log10\"" if x < 0.0
    r = Float.new
    %s(do (log10 (index x 1) (index x 2)) (fstresult r))
    r
  end

  def self.sin(x)
    x = __coerce(x)
    r = Float.new
    %s(do (sin (index x 1) (index x 2)) (fstresult r))
    r
  end

  def self.cos(x)
    x = __coerce(x)
    r = Float.new
    %s(do (cos (index x 1) (index x 2)) (fstresult r))
    r
  end

  def self.tan(x)
    x = __coerce(x)
    r = Float.new
    %s(do (tan (index x 1) (index x 2)) (fstresult r))
    r
  end

  def self.asin(x)
    x = __coerce(x)
    raise DomainError, "Numerical argument is out of domain - \"asin\"" if x < -1.0 || x > 1.0
    r = Float.new
    %s(do (asin (index x 1) (index x 2)) (fstresult r))
    r
  end

  def self.acos(x)
    x = __coerce(x)
    raise DomainError, "Numerical argument is out of domain - \"acos\"" if x < -1.0 || x > 1.0
    r = Float.new
    %s(do (acos (index x 1) (index x 2)) (fstresult r))
    r
  end

  def self.atan(x)
    x = __coerce(x)
    r = Float.new
    %s(do (atan (index x 1) (index x 2)) (fstresult r))
    r
  end

  def self.sinh(x)
    x = __coerce(x)
    r = Float.new
    %s(do (sinh (index x 1) (index x 2)) (fstresult r))
    r
  end

  def self.cosh(x)
    x = __coerce(x)
    r = Float.new
    %s(do (cosh (index x 1) (index x 2)) (fstresult r))
    r
  end

  def self.tanh(x)
    x = __coerce(x)
    r = Float.new
    %s(do (tanh (index x 1) (index x 2)) (fstresult r))
    r
  end

  def self.asinh(x)
    x = __coerce(x)
    r = Float.new
    %s(do (asinh (index x 1) (index x 2)) (fstresult r))
    r
  end

  def self.acosh(x)
    x = __coerce(x)
    raise DomainError, "Numerical argument is out of domain - \"acosh\"" if x < 1.0
    r = Float.new
    %s(do (acosh (index x 1) (index x 2)) (fstresult r))
    r
  end

  def self.atanh(x)
    x = __coerce(x)
    raise DomainError, "Numerical argument is out of domain - \"atanh\"" if x < -1.0 || x > 1.0
    r = Float.new
    %s(do (atanh (index x 1) (index x 2)) (fstresult r))
    r
  end

  def self.atan2(y, x)
    y = __coerce(y)
    x = __coerce(x)
    r = Float.new
    %s(do (atan2 (index y 1) (index y 2) (index x 1) (index x 2)) (fstresult r))
    r
  end

  def self.hypot(a, b)
    a = __coerce(a)
    b = __coerce(b)
    r = Float.new
    %s(do (hypot (index a 1) (index a 2) (index b 1) (index b 2)) (fstresult r))
    r
  end

  # The error function and its complement -- defined for all reals (NaN maps to NaN), no domain errors.
  def self.erf(x)
    x = __coerce(x)
    r = Float.new
    %s(do (erf (index x 1) (index x 2)) (fstresult r))
    r
  end

  def self.erfc(x)
    x = __coerce(x)
    r = Float.new
    %s(do (erfc (index x 1) (index x 2)) (fstresult r))
    r
  end

  # The gamma function. tgamma gives +Infinity at 0 (and -Infinity at -0.0), but a negative integer or
  # negative infinity is a pole/undefined -> Math::DomainError. NaN maps to NaN.
  def self.gamma(x)
    x = __coerce(x)
    return x if x.nan?
    raise DomainError, "Numerical argument is out of domain - \"gamma\"" if x.infinite? == -1
    if x < 0.0 && x == x.floor
      raise DomainError, "Numerical argument is out of domain - \"gamma\""
    end
    # For a positive integer n, gamma(n) is exactly (n-1)!; libm tgamma rounds these (tgamma(9) is
    # 362879.9999...), so compute the factorial exactly (Integer * fixnum only, then to_f). Up to n=171
    # the factorial is finite; beyond that gamma overflows and tgamma's Infinity is correct.
    if x > 0.0 && x <= 171.0 && x == x.floor
      n = x.to_i
      f = 1
      k = 1
      while k < n
        f = f * k
        k = k + 1
      end
      return f.to_f
    end
    r = Float.new
    %s(do (tgamma (index x 1) (index x 2)) (fstresult r))
    r
  end

  # log|gamma| paired with the sign of gamma, as MRI's [value, sign]. The value is libm lgamma (which is
  # +Infinity at the poles 0 and the negative integers); the sign is +1 for x > 0, the sign of the zero
  # for x == 0, and (-1)**floor(x) for a negative non-integer (a negative-integer pole reports +1).
  def self.lgamma(x)
    x = __coerce(x)
    return [x, 1] if x.nan?
    raise DomainError, "Numerical argument is out of domain - \"lgamma\"" if x.infinite? == -1
    v = Float.new
    %s(do (lgamma (index x 1) (index x 2)) (fstresult v))
    [v, __lgamma_sign(x)]
  end

  def self.__lgamma_sign(x)
    return 1 if x > 0.0
    return ((1.0 / x) < 0.0 ? -1 : 1) if x == 0.0   # +0.0 -> 1, -0.0 -> -1
    f = x.floor
    return 1 if x == f                               # negative integer pole
    f.to_i % 2 == 0 ? 1 : -1
  end
end
