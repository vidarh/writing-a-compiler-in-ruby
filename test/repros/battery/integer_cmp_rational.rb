# Integer#<=> (and the relational operators built on it) now handle a Rational operand by promoting
# self to Rational.new(self, 1), instead of falling through to nil. Previously 1 <=> Rational(3,2)
# was nil, so 1 < Rational(3,2) etc. were all false. Float and Integer operands are unchanged.
# Verified against MRI.
p(1 <=> Rational(3, 2))     # -1
p(2 <=> Rational(3, 2))     # 1
p(5 <=> Rational(15, 3))    # 0    (15/3 == 5)
p(1 <=> Rational(1, 2))     # 1
p(1 < Rational(3, 2))       # true
p(2 > Rational(3, 2))       # true
p(5 >= Rational(15, 3))     # true
p(5 <= Rational(15, 3))     # true
p(2 < Rational(3, 2))       # false
# Float / Integer comparisons still behave
p(3 <=> 2.5)                # 1
p(3 <=> 4)                  # -1
p(3 <=> 3)                  # 0
p(1000000000000 <=> Rational(3, 2))   # 1 (bignum vs Rational)
