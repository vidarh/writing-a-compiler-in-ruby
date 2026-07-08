# Numeric#fdiv converts self to a Float and delegates to Float#fdiv, which coerces the divisor via #to_f.
# So a custom Numeric subclass gets fdiv from #to_f, and Integer#fdiv accepts any divisor that answers
# #to_f (previously `self.to_f / other` raised "can't be coerced into Float" for a non-Float). Verified
# vs MRI.
class F < Numeric
  def to_f; 3.0; end
end
p(F.new.fdiv(0.5))   # 6.0   (Numeric#fdiv: 3.0 / 0.5)
p(6.fdiv(F.new))     # 2.0   (Integer#fdiv coerces the custom divisor via #to_f: 6.0 / 3.0)
p(7.5.fdiv(F.new))   # 2.5   (Float#fdiv coerces the divisor: 7.5 / 3.0)
p(3.fdiv(2))         # 1.5
p(1.fdiv(10))        # 0.1
