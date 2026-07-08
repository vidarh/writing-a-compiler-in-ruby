# Numeric#numerator and #denominator convert self to a Rational via #to_r and return that Rational's
# parts, so a custom Numeric subclass gets them for free once it implements #to_r. Integer/Float/Rational
# override with their own; this exercises the Numeric base fallback. Verified vs MRI.
class R2 < Numeric
  def to_r; Rational(3, 4); end
end
p(R2.new.numerator)      # 3
p(R2.new.denominator)    # 4

# built-in numerics keep their own exact behaviour
p(6.numerator)           # 6
p(6.denominator)         # 1
p(Rational(2, 5).numerator)    # 2
p(Rational(2, 5).denominator)  # 5
