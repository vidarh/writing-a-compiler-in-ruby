# Integer heap/heap division (both operands bignums) rounds toward -infinity correctly for a
# negative result. The floor adjustment for a nonzero remainder with differing operand signs must be
# applied AFTER negating the magnitude quotient: floor(-m.frac) == -(m + 1). The old code subtracted
# 1 from the MAGNITUDE before negating, giving -(m - 1) -- e.g. -2 for floor(-3.32) instead of -4.
# This also fixes Rational#ceil/#floor (which are built on Integer floor-division) for large terms.
# Verified against MRI.
n = 1152921504606846976            # 2**60
d = 347029372886660927            # both bignums; n/d ~ 3.322
p(n / d)                           # 3   (positive, unchanged)
p((0 - n) / d)                     # -4  (floor of -3.322)
p(n / (0 - d))                     # -4
p((0 - n) / (0 - d))              # 3   (both negative -> positive)
# exact heap/heap divisions unaffected
p(6000000000000000000 / 3000000000000000000)          # 2
p((0 - 6000000000000000000) / 3000000000000000000)    # -2
# a fixnum divisor path was already correct and stays so
big = 10000000000000000000
p((0 - big) / 3)                   # -3333333333333333334
# Rational rounding now correct for large numerator/denominator
p(Rational.new(n, d).ceil)         # 4
p(Rational.new(n, d).floor)        # 3
p(Rational.new(0 - n, d).floor)    # -4
p(Rational.new(0 - n, d).ceil)     # -3
