# Complex#denominator is the LCM of the two parts' denominators; Complex#numerator scales each part up
# to that common denominator. Verified against MRI.
p(Complex(3, 4).numerator == Complex(3, 4))                       # true
p(Complex(3, 4).denominator == 1)                                 # true
p(Complex(Rational(3, 4), Rational(3, 4)).numerator == Complex(3, 3))   # true
p(Complex(Rational(7, 8), Rational(8, 4)).numerator == Complex(7, 16))  # true
p(Complex(Rational(7, 4), Rational(8, 8)).numerator == Complex(7, 4))   # true
p(Complex(3, Rational(3, 4)).denominator == 4)                    # true
p(Complex(Rational(4, 8), Rational(3, 4)).denominator == 4)       # true
p(Complex(Rational(3, 8), Rational(3, 4)).denominator == 8)       # true
p(Complex(2).numerator == Complex(2))                             # true
