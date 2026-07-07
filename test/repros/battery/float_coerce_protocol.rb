# Float arithmetic (+ - * /) follows MRI's coercion protocol for non-numeric operands: it calls
# other.coerce(self) -> [a, b] and re-applies the operator, so a custom numeric type participates
# and an exception raised inside #coerce propagates. Direct Float/Integer operands are unaffected.
p(1.0 + 2)          # 3.0
p(5.0 - 3)          # 2.0
p(2.0 * 4)          # 8.0
p(10.0 / 4)         # 2.5
class CoNum
  def coerce(o); [o, 10.0]; end
end
p(5.0 + CoNum.new)  # 15.0
p(3.0 * CoNum.new)  # 30.0
p(20.0 / CoNum.new) # 2.0
p(7.5 % 2.0)        # 1.5  (internal caller unaffected)
