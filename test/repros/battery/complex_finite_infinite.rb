# Complex#finite? is true iff BOTH components are finite; Complex#infinite? returns 1 if EITHER
# component is infinite, else nil. Integer/Rational components are always finite. Verified vs MRI.
inf = 1.0 / 0.0
nan = 0.0 / 0.0
p((1 + 1i).finite?)                       # true
p(Complex(1.5, 2.5).finite?)              # true
p(Complex(inf, 42).finite?)               # false
p(Complex(1, inf).finite?)                # false
p(Complex(nan, nan).finite?)              # false
p((1 + 1i).infinite?)                     # nil
p(Complex(inf, 42).infinite?)             # 1
p(Complex(1, inf).infinite?)              # 1
p(Complex(0.0 - inf, 5).infinite?)        # 1
p(Complex(nan, nan).infinite?)            # nil  (NaN is not infinite)
p(Complex(3, 4).finite?)                  # true (Integer parts)
