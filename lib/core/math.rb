# Math module. Each function calls the corresponding libc math.h function DIRECTLY (the double
# argument is passed as its two 32-bit halves; the double result comes back in FPU st0 and is
# captured with fstresult). Domain errors that MRI raises as Math::DomainError are checked here.

module Math
  class DomainError < StandardError
  end

  PI = 3.141592653589793
  E = 2.718281828459045

  def self.sqrt(x)
    x = x.to_f
    raise DomainError, "Numerical argument is out of domain - \"sqrt\"" if x < 0.0
    r = Float.new
    %s(do (sqrt (index x 1) (index x 2)) (fstresult r))
    r
  end

  def self.cbrt(x)
    x = x.to_f
    r = Float.new
    %s(do (cbrt (index x 1) (index x 2)) (fstresult r))
    r
  end

  def self.exp(x)
    x = x.to_f
    r = Float.new
    %s(do (exp (index x 1) (index x 2)) (fstresult r))
    r
  end

  def self.log(x, base = nil)
    x = x.to_f
    raise DomainError, "Numerical argument is out of domain - \"log\"" if x < 0.0
    r = Float.new
    %s(do (log (index x 1) (index x 2)) (fstresult r))
    return r if base.nil?
    r / log(base)
  end

  def self.log2(x)
    x = x.to_f
    raise DomainError, "Numerical argument is out of domain - \"log2\"" if x < 0.0
    r = Float.new
    %s(do (log2 (index x 1) (index x 2)) (fstresult r))
    r
  end

  def self.log10(x)
    x = x.to_f
    raise DomainError, "Numerical argument is out of domain - \"log10\"" if x < 0.0
    r = Float.new
    %s(do (log10 (index x 1) (index x 2)) (fstresult r))
    r
  end

  def self.sin(x)
    x = x.to_f
    r = Float.new
    %s(do (sin (index x 1) (index x 2)) (fstresult r))
    r
  end

  def self.cos(x)
    x = x.to_f
    r = Float.new
    %s(do (cos (index x 1) (index x 2)) (fstresult r))
    r
  end

  def self.tan(x)
    x = x.to_f
    r = Float.new
    %s(do (tan (index x 1) (index x 2)) (fstresult r))
    r
  end

  def self.asin(x)
    x = x.to_f
    raise DomainError, "Numerical argument is out of domain - \"asin\"" if x < -1.0 || x > 1.0
    r = Float.new
    %s(do (asin (index x 1) (index x 2)) (fstresult r))
    r
  end

  def self.acos(x)
    x = x.to_f
    raise DomainError, "Numerical argument is out of domain - \"acos\"" if x < -1.0 || x > 1.0
    r = Float.new
    %s(do (acos (index x 1) (index x 2)) (fstresult r))
    r
  end

  def self.atan(x)
    x = x.to_f
    r = Float.new
    %s(do (atan (index x 1) (index x 2)) (fstresult r))
    r
  end

  def self.sinh(x)
    x = x.to_f
    r = Float.new
    %s(do (sinh (index x 1) (index x 2)) (fstresult r))
    r
  end

  def self.cosh(x)
    x = x.to_f
    r = Float.new
    %s(do (cosh (index x 1) (index x 2)) (fstresult r))
    r
  end

  def self.tanh(x)
    x = x.to_f
    r = Float.new
    %s(do (tanh (index x 1) (index x 2)) (fstresult r))
    r
  end

  def self.asinh(x)
    x = x.to_f
    r = Float.new
    %s(do (asinh (index x 1) (index x 2)) (fstresult r))
    r
  end

  def self.acosh(x)
    x = x.to_f
    raise DomainError, "Numerical argument is out of domain - \"acosh\"" if x < 1.0
    r = Float.new
    %s(do (acosh (index x 1) (index x 2)) (fstresult r))
    r
  end

  def self.atanh(x)
    x = x.to_f
    raise DomainError, "Numerical argument is out of domain - \"atanh\"" if x < -1.0 || x > 1.0
    r = Float.new
    %s(do (atanh (index x 1) (index x 2)) (fstresult r))
    r
  end

  def self.atan2(y, x)
    y = y.to_f
    x = x.to_f
    r = Float.new
    %s(do (atan2 (index y 1) (index y 2) (index x 1) (index x 2)) (fstresult r))
    r
  end

  def self.hypot(a, b)
    a = a.to_f
    b = b.to_f
    r = Float.new
    %s(do (hypot (index a 1) (index a 2) (index b 1) (index b 2)) (fstresult r))
    r
  end
end
