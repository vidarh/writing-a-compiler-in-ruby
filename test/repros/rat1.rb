# Rational arithmetic, comparison and rounding (lib/core/rational.rb). Every line below prints
# identically under MRI and the self-hosted compiler (the one Float-dependent op, #to_f, is
# deliberately omitted since Float is still stubbed). Guards the +55%-assertion Rational feature.
p(Rational(3, 4) + Rational(1, 4))   # (1/1)
p(Rational(3, 4) - Rational(1, 2))   # (1/4)
p(Rational(3, 4) * 2)                # (3/2)
p(Rational(3, 4) / Rational(1, 2))   # (3/2)
p(Rational(6, 8) == Rational(3, 4))  # true  (normalised)
p(Rational(1, -2))                   # (-1/2) (sign carried to numerator)
p(2 + Rational(1, 2))                # (5/2)  (Integer promotes)
p(7 / Rational(2, 1))                # (7/2)
p(7 % Rational(3, 1))                # (1/1)
p(Rational(2, 3) ** 2)               # (4/9)
p(Rational(2, 3) ** -1)              # (3/2)
p(Rational(-7, 2).floor)             # -4
p(Rational(-7, 2).ceil)              # -3
p(Rational(5, 2).round)              # 3   (half away from zero)
p(Rational(-7, 2).truncate)          # -3  (toward zero)
p(Rational(3, 4).floor(1))           # (7/10)  digit-precision floor
p(Rational(3, 4).ceil(1))            # (4/5)   digit-precision ceil
p(Rational(3, 4).round(1))           # (4/5)   digit-precision round
p(Rational(1, 3).truncate(2))        # (33/100)
p(7.quo(2))                          # (7/2)   Integer#quo -> exact Rational
p(7.quo(Rational(1, 2)))             # (14/1)
p(Rational(1, 2) < Rational(2, 3))   # true
p(Rational(1, 1) == 1)               # true
p(Rational(-7, 2).to_i)              # -3
p(Rational("3/4"))                   # (3/4)  Kernel#Rational parses a String
p(Rational("3", "4"))                # (3/4)
p(Rational(Rational(1, 2), 3))       # (1/6)  Rational arg combined by division
p(Rational(3, 2).clamp(Rational(0, 1), Rational(1, 1)))  # (1/1)
p(Rational(3, 4).between?(Rational(0, 1), Rational(1, 1)))  # true
p((-7).remainder(3))                 # -1  remainder has sign of dividend (not modulo's 2)
p(7.remainder(-3))                   # 1
