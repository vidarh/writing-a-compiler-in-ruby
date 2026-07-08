# Rational#% (== #modulo) and #divmod raise ZeroDivisionError for a zero divisor -- Integer 0, Rational
# 0, or Float 0.0 -- rather than letting a Float 0.0 flow through to an Infinity/NaN result. Non-zero
# divisors compute normally. Verified vs MRI.
def try
  begin
    yield.inspect
  rescue => e
    e.class.to_s
  end
end
p(try { Rational(1, 2) % 0.0 })                 # "ZeroDivisionError"
p(try { Rational(1, 2) % 0 })                   # "ZeroDivisionError"
p((Rational(7, 2) % Rational(1, 3)).to_s)       # "1/6"
p(try { Rational(1, 2).divmod(0.0) })           # "ZeroDivisionError"
p(try { Rational(1, 2).divmod(0) })             # "ZeroDivisionError"
dm = Rational(7, 3).divmod(Rational(1, 2))
p([dm[0], dm[1].to_s])                          # [4, "1/3"]
