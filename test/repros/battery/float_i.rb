# Numeric#i returns the Complex 0 + self*i; Float needs its own copy (not a Numeric subclass here).
# Verified vs MRI.
p(62.81.i.class == Complex)              # true
p(62.81.i.real)                          # 0
p(62.81.i.imag)                          # 62.81
p(3.i.imag)                              # 3   (Integer, via Numeric#i)
p(3.i.real)                              # 0
p(Rational(1, 2).i.imag == Rational(1, 2))  # true (Rational, via Numeric#i)
p((-2.5).i.imag)                         # -2.5
