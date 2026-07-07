# Integer#** with a negative exponent returns the exact reciprocal as a Rational (MRI), not the
# integer-divided 0 it used to. self == 0 still raises ZeroDivisionError; +/-1 stay integers.
# Verified against MRI. (This is what made Float::MAX's spec formula (1 + (1 - 2**-52)) * 2.0**1023
# overflow to Infinity: with 2**-52 == 0 the product was 2 * 2**1023 == 2**1024 == Infinity.)
p(2 ** -52)                # (1/4503599627370496)
p((2 ** -52).class)        # Rational
p(10 ** -2)                # (1/100)
p(3 ** -1)                 # (1/3)
p((-2) ** -3)              # (-1/8)
p(1 ** -5)                 # 1    (self == 1 short-circuit, Integer)
p((-1) ** -4)              # 1    (self == -1 short-circuit, Integer)
p((-1) ** -3)              # -1
# the constants formula now evaluates finite and equal to Float::MAX
p(Float::MAX == (1 + (1 - (2 ** -52))) * (2.0 ** 1023))  # true
def try(&b)
  begin
    b.call
    p "no-raise"
  rescue => e
    p e.class.to_s
  end
end
try { 0 ** -1 }            # "ZeroDivisionError"
