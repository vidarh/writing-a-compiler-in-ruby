# Math.log(x) is the natural log; Math.log(x, base) divides by log(base). The base defaults to a
# sentinel, so an EXPLICIT nil base raises TypeError (nil is not a valid base) while the no-base call
# returns the natural log. Verified against MRI.
def close(a,b); (a-b).abs < 0.00001; end
p(close(Math.log(Math::E), 1.0))    # true (natural log, no base)
p(close(Math.log(9, 3), 2.0))       # true (base 3)
p(close(Math.log(8, 2), 3.0))       # true
p(close(Math.log(100, 10), 2.0))    # true
def t
  begin
    yield
    p "no-raise"
  rescue => e
    p e.class.to_s
  end
end
t { Math.log(10, nil) }             # "TypeError"  (explicit nil base)
t { Math.log(10, "2") }             # "TypeError"  (string base)
t { Math.log(-0.5) }                # "Math__DomainError"
