# Complex#to_c returns self. to_i/to_f require an EXACT-zero imaginary part (Integer/Rational 0, not
# Float 0.0) and send #to_i/#to_f to the real part, else RangeError. to_r accepts ANY zero imaginary
# part (including Float 0.0, per Ruby 3.4) and sends #to_r to the real part, else RangeError.
# Verified against MRI.
v = Complex(1, 5)
p(v.to_c.equal?(v))              # true (returns self)
p(Complex(3, 0).to_i == 3)       # true
p(Complex(7, 0).to_f == 7.0)     # true
p(Complex(3, 0).to_r == Rational(3, 1))  # true
p(Complex(3, Rational(0)).to_i == 3)     # true (Rational 0 is exact)
p(Complex(0, 0.0).to_r == Rational(0))   # true (to_r accepts Float 0.0)
def try(&b)
  begin
    b.call
    p "no-raise"
  rescue => e
    p e.class.to_s
  end
end
try { Complex(0, 1).to_i }       # "RangeError"
try { Complex(0, 0.0).to_i }     # "RangeError" (Float 0.0 not exact for to_i)
try { Complex(0, 0.0).to_f }     # "RangeError"
try { Complex(0, 2).to_r }       # "RangeError" (non-zero imag)
