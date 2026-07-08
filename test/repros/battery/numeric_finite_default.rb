# Numeric#finite? returns true by default (a real number is always finite). Integer and Rational have
# no #finite? of their own, so they inherit this Numeric default; Float overrides it for Infinity/NaN.
# Numeric#ceil (the base fallback) delegates to to_f.ceil, but Integer/Float/Rational all override with
# their own exact #ceil, verified here. Values verified vs MRI.
p(5.finite?)               # true   (Integer -> Numeric#finite?)
p(0.finite?)               # true
p(Rational(3, 4).finite?)  # true   (Rational -> Numeric#finite?)
p(2.5.finite?)             # true   (Float#finite?)
p(5.ceil)                  # 5      (Integer#ceil)
p(3.2.ceil)                # 4      (Float#ceil)
p(Rational(7, 2).ceil)     # 4      (Rational#ceil: 3.5 -> 4)
