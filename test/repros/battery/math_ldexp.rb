# Math.ldexp(frac, n) = frac * 2**n. frac coerces to Float (String -> TypeError); the exponent coerces
# to Integer (Float truncates, NaN/Infinity -> RangeError, non-numeric -> TypeError) and is passed to
# libc ldexp as a raw int. Verified against MRI.
def close(a,b); (a-b).abs < 0.00001; end
p(Math.ldexp(1.0, 3) == 8.0)          # true
p(close(Math.ldexp(-1.25, 2), -5.0)) # true
p(close(Math.ldexp(2.1, -3), 0.2625))# true
p(Math.ldexp(0.0, 5) == 0.0)          # true
p(Math.ldexp(1, 4) == 16.0)           # true (Integer frac coerces)
p(Math.ldexp(3.0, 0.0) == 3.0)        # true (Float exponent truncates)
p(Math.ldexp(0.0/0.0, 0).nan?)        # true (NaN frac)
p(Math.ldexp(1.0, 2).class)           # Float
def try(&b)
  begin
    b.call
    p "no-raise"
  rescue => e
    p e.class.to_s
  end
end
try { Math.ldexp("test", 2) }         # "TypeError" (bad frac)
try { Math.ldexp(3.2, "this") }       # "TypeError" (bad exponent)
try { Math.ldexp(0, 0.0/0.0) }        # "RangeError" (NaN exponent)
