# Float#** with a Float/Rational exponent: real result via libm pow, except a negative base with a
# fractional exponent, which is Complex (self**e = |self|**e * (cos(e*pi) + i*sin(e*pi))). Complex#abs
# is the magnitude sqrt(a**2+b**2). Integer exponents keep the exponentiation-by-squaring path.
# Verified against MRI (values shown to the precision the compiler prints).
p((9.5 ** 0.5))              # 3.082207001484488
p((2.0 ** 10.0))            # 1024.0
p((8.0 ** (1.0 / 3)))       # 2.0
p((5.2 ** -1))              # 0.1923076923076923  (integer exponent, reciprocal)
p((2.3 ** 3))               # 12.166999999999996   (integer exponent)
p((9.5 ** 0xffffffff).to_s) # "Infinity"  (huge integer exponent overflows)
p((4.0 ** Rational(1, 2)))  # 2.0  (Rational exponent, positive base)
# negative base + fractional exponent -> Complex
c = (-8.0) ** (1.0 / 3)
p(c.class)                  # Complex
p(c.real.round(6))          # 1.0
p(c.imag.round(6))          # 1.732051
d = (-8.0) ** Rational(1, 3)
p(d.imag.round(6))          # 1.732051
# Complex#abs / #magnitude
p(Complex(3, 4).abs)        # 5.0
p(Complex(3, 4).magnitude)  # 5.0
p(Complex(0, 2).abs)        # 2.0
