# A Float is a real number: #real? is true, #real is self, #imaginary (aliased #imag) is 0. These are
# the standard Numeric predicates (Integer already had #real?). Verified against MRI.
p(5.0.real?)          # true
p((0.0 / 0.0).real?)  # true  (even NaN is a "real" Float)
p((1.0 / 0.0).real?)  # true  (Infinity too)
p(5.0.real == 5.0)    # true
p((-2.5).real == -2.5) # true
p(5.0.imaginary == 0) # true
p(5.0.imag == 0)      # true
p(3.14.imaginary == 0) # true
