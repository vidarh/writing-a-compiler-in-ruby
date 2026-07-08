# Math functions now coerce their argument strictly (via Math.__coerce): an Integer/Rational converts,
# but a String or nil is a TypeError -- a bare x.to_f would silently turn "test" into 0.0. Valid
# numeric arguments are unaffected. Verified against MRI.
def close(a, b); (a - b).abs < 0.00001; end
p(close(Math.sin(0), 0.0))          # true (Integer arg coerces)
p(close(Math.sqrt(4), 2.0))         # true
p(close(Math.cos(0), 1.0))          # true
p(close(Math.log(Math::E), 1.0))    # true
p(close(Math.atan2(1, 1), 0.7853981633974483))  # true (both args coerce)
p(close(Math.hypot(3, 4), 5.0))     # true
def try(&b)
  begin
    b.call
    p "no-raise"
  rescue => e
    p e.class.to_s
  end
end
try { Math.sin("test") }     # "TypeError"
try { Math.sqrt(nil) }       # "TypeError"
try { Math.cos(nil) }        # "TypeError"
try { Math.log("x") }        # "TypeError"
try { Math.atan2("a", 1) }   # "TypeError"
try { Math.hypot(3, nil) }   # "TypeError"
# domain errors still raised
try { Math.sqrt(-1) }        # "Math__DomainError"
try { Math.acos(2) }         # "Math__DomainError"
