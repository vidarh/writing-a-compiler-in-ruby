# Float#rationalize returns the SIMPLEST rational within a tolerance (unlike to_r, which is exact).
# No argument uses self's own representable interval (from prev_float/next_float); one argument uses
# +/- that value. The simplest rational in the interval is found by a continued-fraction walk.
# NaN/Infinity raise FloatDomainError; more than one argument raises ArgumentError. vs MRI.
p(3382729202.92822.rationalize)         # (4806858197361/1421)
p(0.3.rationalize(Rational(1, 10)))     # (1/3)
p(0.3.rationalize(Rational(-1, 10)))    # (1/3)  (tolerance magnitude)
p((-0.3).rationalize(Rational(1, 10)))  # (-1/3)
p(0.3.rationalize(0.05))                # (1/3)
p(0.3.rationalize(0.001))               # (3/10)
p((-0.3).rationalize(0.05))             # (-1/3)
p(0.3.rationalize.class)                # Rational
def try(&b)
  begin
    b.call
    p "no-raise"
  rescue => e
    p e.class.to_s
  end
end
try { (1.0 / 0.0).rationalize }         # "FloatDomainError"
try { (0.0 / 0.0).rationalize }         # "FloatDomainError"
try { 0.3.rationalize(0.1, 0.1) }       # "ArgumentError"
