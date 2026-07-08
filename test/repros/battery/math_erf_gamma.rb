# Math.erf / erfc / gamma / lgamma -- thin libm wrappers (erf/erfc/tgamma/lgamma), each called with the
# double argument as its two 32-bit halves and the st0 result captured. gamma special-cases a positive
# integer n to return the exact (n-1)! (libm tgamma rounds those, e.g. tgamma(9)=362879.9999); a
# negative integer or -Infinity is a Math::DomainError. lgamma returns [log|gamma|, sign of gamma].
# Args coerce strictly (String/nil -> TypeError). Verified against MRI.
def close(a, b); (a - b).abs < 0.00001; end
p(close(Math.erf(1), 0.842700792949715))     # true
p(close(Math.erf(-1), -0.842700792949715))   # true
p(Math.erf(0) == 0.0)                          # true
p(close(Math.erfc(1), 0.157299207050285))    # true
p(Math.gamma(0) == Float::INFINITY)            # true
p(Math.gamma(5) == 24)                         # true  (exact factorial 4!)
p(Math.gamma(9) == 40320)                      # true  (8!, tgamma rounds this)
p(close(Math.gamma(0.5), Math.sqrt(Math::PI)))  # true
p(Math.gamma(24).class)                        # Float
lg = Math.lgamma(0)
p(lg == [Float::INFINITY, 1])                  # true
lg2 = Math.lgamma(-0.0)
p(lg2[1] == -1)                                # true  (sign of gamma at -0.0)
lg3 = Math.lgamma(-0.5)
p(lg3[1] == -1)                                # true
p(close(Math.lgamma(6.0)[0], Math.log(120.0)))  # true
def try(&b)
  begin
    b.call
    p "no-raise"
  rescue => e
    p e.class.to_s
  end
end
try { Math.erf("test") }         # "TypeError"
try { Math.erf(nil) }            # "TypeError"
try { Math.gamma(-1) }           # "Math::DomainError"  (prints as DomainError)
try { Math.gamma(0.0 - (1.0/0.0)) }   # DomainError (-Infinity)
p(Math.gamma(0.0/0.0).nan?)      # true  (NaN)
p(Math.gamma(1.0/0.0) == Float::INFINITY)   # true  (+Infinity)
