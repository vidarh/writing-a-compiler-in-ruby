# Complex#coerce: a Complex pairs as [other, self]; a real numeric (Integer/Float/Rational, or a custom
# real Numeric) wraps as [Complex(other, 0), self]; a non-real Numeric or a non-numeric (String, etc.)
# raises TypeError. Verified against MRI.
one = Complex(1)
r = one.coerce(2)
p(r[0] == Complex(2) && r[1] == Complex(1))   # true
p(r[0].is_a?(Complex))                         # true
p(one.coerce(20.5)[0] == Complex(20.5))        # true (Float)
p(one.coerce(Rational(5, 6))[0] == Complex(Rational(5, 6)))  # true
oc = Complex(2)
rc = one.coerce(oc)
p(rc[0].equal?(oc) && rc[1].equal?(one))       # true (Complex passes through)
def try(&b)
  begin
    b.call
    p "no-raise"
  rescue => e
    p e.class.to_s
  end
end
try { one.coerce("string") }                   # "TypeError"
try { one.coerce(Object.new) }                 # "TypeError"
