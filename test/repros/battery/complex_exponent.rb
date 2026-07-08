# Complex#**: an Integer exponent is exact via repeated multiplication (negative -> reciprocal); a real
# (Float/Rational) exponent uses the polar form |z|**w*(cos(arg*w)+i*sin(arg*w)); a Complex exponent
# uses exp(w*log z). Verified against MRI.
def close(a, b); (a - b).abs < 0.0001; end
p(Complex(2, 1) ** 2 == Complex(3, 4))         # true (exact)
p(Complex(3, 4) ** 2 == Complex(-7, 24))       # true
p(Complex(1) ** 1 == Complex(1))               # true
p((Complex(3, 4) ** 0) == Complex(1))          # true (Integer 0)
p((Complex(3, 4) ** 0.0).real == 1.0)          # true (Float 0.0 -> Complex(1.0, 0.0))
p((Complex(3, 4) ** 0.0).imag == 0.0)          # true
# negative integer exponent (reciprocal)
n2 = Complex(3, 4) ** -2
p(close(n2.real, -0.0112))                      # true
p(close(n2.imag, -0.0384))                      # true
# float exponent (polar)
f = Complex(3, 4) ** 2.5
p(close(f.real, -38.0))                         # true
p(close(f.imag, 41.0))                          # true
# complex exponent (exp(w log z))
c = Complex(2, 1) ** Complex(2, 1)
p(close(c.real, -0.504824688978319))            # true
p(close(c.imag, 3.10414407699553))              # true
