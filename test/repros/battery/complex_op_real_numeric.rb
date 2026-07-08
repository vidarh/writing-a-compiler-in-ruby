# Complex arithmetic against a custom real Numeric (one that answers #real? with true but is not a
# built-in Integer/Float/Rational) operates component-wise -- Complex(@real OP other, @imag [OP other])
# -- letting the component operator drive coercion. Against a non-real operand it falls back to
# `other.coerce(self)` and applies the op; division coerces via :quo, so integer operands divide
# exactly to a Rational (5 / 2 -> (5/2)) rather than truncating to 2. Verified vs MRI.

# real? => true : component-wise, `@real +/- other` triggers the component's coerce (coerce(1) -> [1,4])
class RN < Numeric
  def real?; true; end
  def coerce(o); [o, 4]; end
end
p((Complex(1, 2) + RN.new).to_s)   # "5+2i"   (1 + RN -> 1.coerce path -> 1+4=5)
p((Complex(1, 2) - RN.new).to_s)   # "-3+2i"  (1 - 4 = -3)

# real? => false : coerce fallback; division uses :quo so 5/2 stays exact
class NR < Numeric
  def real?; false; end
  def coerce(o); [5, 2]; end
end
p((Complex(3, 0) / NR.new).to_s)     # "5/2"
p((Complex(3, 0).quo(NR.new)).to_s)  # "5/2"
