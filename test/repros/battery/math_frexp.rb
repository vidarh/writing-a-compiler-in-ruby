# Math.frexp(x) -> [fraction, exponent] with x == fraction * 2**exponent and 0.5 <= |fraction| < 1
# (or [0.0, 0] for 0). libc frexp returns the fraction in st0 and writes the exponent through an int*;
# a one-slot buffer is passed for it and read back. The argument coerces to Float (String/nil ->
# TypeError). Verified against MRI.
def close(a,b); (a-b).abs < 0.00001; end
r = Math.frexp(102.83)
p(close(r[0], 0.803359375))    # true
p(r[1] == 7)                    # true
p(Math.frexp(8.0) == [0.5, 4])  # true
p(Math.frexp(0.25) == [0.5, -1]) # true
p(Math.frexp(0.0) == [0.0, 0])  # true
p(Math.frexp(6.0) == [0.75, 3]) # true
p(Math.frexp(1) == [0.5, 1])    # true (Integer coerces)
fn = Math.frexp(0.0/0.0)
p(fn[0].nan?)                   # true (NaN)
def try(&b)
  begin
    b.call
    p "no-raise"
  rescue => e
    p e.class.to_s
  end
end
try { Math.frexp("test") }      # "TypeError"
try { Math.frexp(nil) }         # "TypeError"
