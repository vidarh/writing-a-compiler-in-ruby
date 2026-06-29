
class Complex
  def imag
    @imag
  end

  def real
    @real
  end

  def initialize(real, imag = 0)
    @real=real
    @imag=imag
  end
end

# Ruby: Complex(real, imaginary = 0) -- the imaginary part is optional, so a 1-arg call must not raise
# ArgumentError (which crashed every complex spec whose fixtures build Complex(n) at load).
def Complex(a, b = 0)
  Complex.new(a, b)
end
