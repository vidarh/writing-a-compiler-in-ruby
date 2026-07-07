# Float#to_r (exact), #numerator, #denominator, and Kernel#Rational(Float). to_r scales |self| into
# [2**52, 2**53) by exact *2 / /2 (binary floats shift the exponent losslessly), reads the integer
# mantissa with to_i, and pairs it with the tracked power of two; Rational.new reduces via gcd.
# numerator/denominator are its parts (NaN -> self / 1; Infinity -> self / 1). Verified against MRI.
p(6.0.to_r)              # (6/1)
p(0.5.to_r)              # (1/2)
p(0.25.to_r)             # (1/4)
p((-2.5).to_r)           # (-5/2)
p(0.0.to_r)              # (0/1)
p((-0.0).to_r)           # (0/1)
p(1.4592.to_r)           # (1642913144064757/1125899906842624)
p(6.0.numerator)         # 6
p(6.0.denominator)       # 1
p(1.4592.denominator)    # 1125899906842624
p(0.0.numerator)         # 0
p((0.0).denominator)     # 1
# Rational(Float) now delegates to Float#to_r, so it matches numerator/denominator by construction
p(Rational(0.5))         # (1/2)
p(Rational(1.4592) == 1.4592.to_r)   # true
p(29871.22736282.denominator.is_a?(Integer))   # true
# NaN / Infinity have no rational value
nan = 0.0 / 0.0
inf = 1.0 / 0.0
p(nan.numerator.nan?)    # true
p(inf.numerator.infinite?)   # 1
p(nan.denominator)       # 1
p(inf.denominator)       # 1
# pre-existing Rational() forms still work
p(Rational(1, 2))        # (1/2)
p(Rational("3/4"))       # (3/4)
p(Rational(6, 3))        # (2/1)
