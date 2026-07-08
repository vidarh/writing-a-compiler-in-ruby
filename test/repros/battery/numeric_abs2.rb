# Numeric#abs2 (and Float#abs2, since Float is not a Numeric subclass here) is the square of the
# absolute value: self*self. Correct for negatives, and NaN/Infinity propagate through the multiply.
# Verified vs MRI.
p(5.abs2)            # 25
p((-5).abs2)         # 25
p(0.abs2)            # 0
p(3.5.abs2)          # 12.25
p((-3.5).abs2)       # 12.25
inf = 1e300 * 1e300  # Infinity
p(inf.abs2)          # Infinity
nan = 0.0 / 0.0
p(nan.abs2.nan?)     # true
