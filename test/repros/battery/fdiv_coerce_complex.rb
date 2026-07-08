# fdiv across the numeric tower. Complex#fdiv divides component-wise by a real divisor and does full
# complex division by a Complex divisor (breaking the Float#fdiv(Complex) coerce cycle that previously
# recursed to a SIGSEGV). Float#fdiv / Integer#fdiv accept a real numeric (convert via #to_f), otherwise
# apply the coercion protocol (`other.coerce(self)` -> [a,b]; a.fdiv(b)), and a value that is neither
# numeric nor coercible (Array, Symbol, String -- which HAS #to_f but is not Numeric) is a TypeError.
# Verified vs MRI.
class Co
  def coerce(o); [1, 10]; end
end
def try
  begin
    yield.inspect
  rescue => e
    e.class.to_s
  end
end

p(Complex(20).fdiv(2).inspect)                  # "(10.0+0.0i)"
p(74620.09.fdiv(Complex(8, 2)).inspect)         # "(8778.834117647059-2194.7085294117646i)"
p(Complex(1, 2).fdiv(Complex(2, 0)).inspect)    # "(0.5+1.0i)"   (complex division, no recursion)
p(1.fdiv(Co.new))                               # 0.1           (Integer#fdiv coerce protocol)
p(try { 6.fdiv([]) })                           # "TypeError"
p(try { 6.0.fdiv("s") })                        # "TypeError"   (String has #to_f but is not Numeric)
p(try { Complex(20).fdiv(:sym) })               # "TypeError"   (propagated from the component fdiv)
nan = 0.0 / 0.0
p(Complex(nan).fdiv(2).real.nan?)               # true
