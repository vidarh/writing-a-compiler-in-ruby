# Complex.rectangular / Complex.rect build a Complex from real & imaginary parts (both must be real
# numerics; a Complex/nil/String is a TypeError). Complex::I is the imaginary unit Complex(0, 1).
# Verified against MRI.
p(Complex.rectangular(3, 4) == Complex(3, 4))   # true
p(Complex.rect(5) == Complex(5, 0))             # true (imag defaults to 0)
p(Complex.rect(1.5, -2.5) == Complex(1.5, -2.5)) # true
p(Complex::I == Complex(0, 1))                   # true
p(Complex::I.real == 0)                          # true
p(Complex::I.imag == 1)                          # true
# I behaves as the imaginary unit
p(Complex::I * Complex::I == Complex(-1, 0))     # true (i^2 == -1)
def try(&b)
  begin
    b.call
    p "no-raise"
  rescue => e
    p e.class.to_s
  end
end
try { Complex.rectangular(nil) }                 # "TypeError"
try { Complex.rect("x", 1) }                     # "TypeError"
try { Complex.rectangular(Complex(1,2), 3) }     # "TypeError" (non-real arg)
