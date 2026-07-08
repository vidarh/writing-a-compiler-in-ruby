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

  # log(x) is the natural log; log(x, base) divides by log(base). The base defaults to a sentinel so an
  # EXPLICIT nil base (Math.log(10, nil)) coerces and raises TypeError, unlike the no-base call.
  def self.log(x, base = :__nobase)
    x = __coerce(x)
    raise DomainError, "Numerical argument is out of domain - \"log\"" if x < 0.0
    r = Float.new
    %s(do (log (index x 1) (index x 2)) (fstresult r))
    return r if base == :__nobase
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

  # Coerce the exponent argument of ldexp to an Integer with Integer()-like strictness: an Integer is
  # used as-is; a finite Float is truncated; a NaN/Infinity Float is a RangeError; anything without
  # #to_int (a String, nil, ...) is a TypeError.
  def self.__coerce_int(n)
    return n if n.is_a?(Integer)
    if n.is_a?(Float)
      raise RangeError, "float #{n} out of range of integer" if n.nan? || !n.infinite?.nil?
      return n.to_i
    end
    unless n.respond_to?(:to_int)
      raise TypeError, "no implicit conversion of #{n.nil? ? "nil" : n.class} into Integer"
    end
    n.to_int
  end

  # ldexp(frac, n) = frac * 2**n. The exponent is passed to libc ldexp as a raw (untagged) int.
  def self.ldexp(frac, n)
    frac = __coerce(frac)
    n = __coerce_int(n)
    r = Float.new
    %s(do (ldexp (index frac 1) (index frac 2) (sar n)) (fstresult r))
    r
  end

  # frexp(x) -> [fraction, exponent] with x == fraction * 2**exponent and 0.5 <= |fraction| < 1 (or 0).
  # libc frexp returns the fraction in st0 and writes the exponent through an int* -- a one-slot buffer
  # is passed for it and read back.
  def self.frexp(x)
    x = __coerce(x)
    e = 0
    frac = Float.new
    %s(let (buf)
      (assign buf (__array 1))
      (do (frexp (index x 1) (index x 2) buf) (fstresult frac))
      (assign e (__int (index buf 0))))
    [frac, e]
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
