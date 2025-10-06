
class Complex
  def imag
    @imag
  end

  def real
    @real
  end

  def initialize(imag,real)
    @imag=imag
    @real=real
  end
end

def Complex(a,b)
  Complex.new(a,b)
end
