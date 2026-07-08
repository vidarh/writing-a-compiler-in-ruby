# Complex.rectangular / .rect accept a real part that is any real Numeric -- a built-in Integer/Float/
# Rational OR a custom Numeric answering #real? with true -- not only the built-in three. A non-real
# Numeric (#real? false) or a non-Numeric (Symbol, nil) is a TypeError. Verified vs MRI.
class RN < Numeric
  def real?; true; end
end
class NR < Numeric
  def real?; false; end
end
n = RN.new
c = Complex.rectangular(n)
p(c.real.equal?(n))   # true  -- the real part is n itself
p(c.imag)             # 0

def try
  begin
    yield
    "no-raise"
  rescue => e
    e.class.to_s
  end
end
p(try { Complex.rectangular(NR.new) })   # "TypeError"  -- real? false
p(try { Complex.rectangular(:sym) })     # "TypeError"  -- non-Numeric
p(try { Complex.rectangular(nil) })      # "TypeError"
