# Complex#rationalize forwards to the real part's #rationalize when the imaginary part is an EXACT zero
# (else RangeError; >1 arg -> ArgumentError). Complex#<=> orders only when BOTH operands are real,
# comparing the real parts; otherwise nil. Verified against MRI.
p(Complex(1, 0).rationalize == Rational(1, 1))       # true
p(Complex(1, 0).rationalize(0.1) == Rational(1, 1))  # true (arg ignored by Integer#rationalize)
p((Complex(5) <=> Complex(2)) == 1)                  # true
p((Complex(2) <=> Complex(3)) == -1)                 # true
p((Complex(2) <=> Complex(2)) == 0)                  # true
p((Complex(5) <=> 2) == 1)                           # true
p((Complex(5, 1) <=> Complex(2)).nil?)               # true (self has imaginary part)
p((Complex(1) <=> Complex(2, 1)).nil?)               # true (other has imaginary part)
p((Complex(5, 1) <=> "cmp").nil?)                    # true (non-numeric)
p((Complex(1) <=> Object.new).nil?)                  # true
def try(&b)
  begin
    b.call
    p "no-raise"
  rescue => e
    p e.class.to_s
  end
end
try { Complex(1, 5).rationalize }                    # "RangeError"
try { Complex(1, 0.0).rationalize }                  # "RangeError" (Float 0.0 not exact)
try { Complex(1, 0).rationalize(0.1, 0.1) }          # "ArgumentError"
