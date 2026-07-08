# Rational#floor/#ceil/#truncate/#round require an Integer digit-precision argument; anything else
# (nil, a Float, a String, an arbitrary object) is a TypeError "not an integer" and #to_int is NOT called.
# An Integer argument (including the default 0) works normally. Verified vs MRI.
def try
  begin
    yield.inspect
  rescue => e
    e.class.to_s
  end
end
r = Rational(7, 4)
p(try { r.truncate(nil) })   # "TypeError"
p(try { r.truncate(1.0) })   # "TypeError"
p(try { r.truncate('') })    # "TypeError"
p(try { r.floor(nil) })      # "TypeError"
p(try { r.ceil(1.0) })       # "TypeError"
p(try { r.round('') })       # "TypeError"
p(r.truncate)                # 1
p(r.truncate(0))             # 1
p(r.floor)                   # 1
p(r.ceil)                    # 2
