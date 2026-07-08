# Complex#arg (aliases angle/phase) is the phase angle atan2(imag, real). Complex#polar returns
# [magnitude, argument]. Complex.polar(r, theta=0) builds r*cos(theta) + r*sin(theta)*i; a non-real
# argument (nil, String, non-real Complex) is a TypeError. Verified against MRI.
def close(a,b); (a-b).abs < 0.00001; end
p(Complex(1, 0).arg == 0.0)                   # true
p(close(Complex(0, 2).arg, Math::PI/2))       # true
p(close(Complex(-100, 0).arg, Math::PI))      # true
p(close(Complex(3, 4).angle, 0.927295218001612))  # true (alias)
p(close(Complex(3, 4).phase, 0.927295218001612))  # true (alias)
# instance polar
pl = Complex(3, 4).polar
p(pl.size == 2)                                # true
p(pl[0] == 5.0)                                # true
p(close(pl[1], 0.927295218001612))            # true
# class polar
c = Complex.polar(50, 60)
p(close(c.real, -47.6206490207578))           # true
p(close(c.imag, -15.2405310551108))           # true
p(close(Complex.polar(5).real, 5.0))          # true (theta defaults to 0)
def try(&b)
  begin
    b.call
    p "no-raise"
  rescue => e
    p e.class.to_s
  end
end
try { Complex.polar(nil) }                     # "TypeError"
try { Complex.polar(nil, nil) }                # "TypeError"
