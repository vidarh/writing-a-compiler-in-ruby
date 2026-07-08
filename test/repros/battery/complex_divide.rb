# Complex#/ (and #quo): (a+bi)/(c+di) = (a+bi)(c-di)/(c**2+d**2). abs2 is the real denominator, so no
# square root is needed. Components divide with #quo, so integer components give exact Rationals and
# Float components stay Float. This also lets Float#fdiv / #quo divide by a Complex (Complex has no
# #to_f, so they route through Float#/ -> the coercion protocol -> Complex#/). Verified against MRI.
p(Complex(1, 2) / Complex(1, 1))       # ((3/2)+(1/2)*i)
p(Complex(10, 20) / 5)                 # ((2)+(4)*i)  (Rational components)
p(Complex(8, 2) / Complex(8, 2))       # ((1)+(0)*i)
p(74620.09 / Complex(8, 2))            # (8778.834117647059-2194.7085294117646i)
p(74620.09.fdiv(Complex(8, 2)))        # same
p(74620.09.quo(Complex(8, 2)))         # same
# real-operand division still fine
p(74620.09.fdiv(Rational(2, 3)))       # 111930.135
p(2827.22.fdiv(0.0).infinite?)         # 1
def try(&b)
  begin
    b.call
    p "no-raise"
  rescue => e
    p e.class.to_s
  end
end
try { 27292.2.fdiv(Object.new) }       # "TypeError"  (non-numeric)
