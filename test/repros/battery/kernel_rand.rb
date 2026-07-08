# Kernel#rand (global) delegates to the default Random. No argument returns a Float in [0, 1); an
# Integer limit returns an Integer in [0, limit); a Float limit returns a Float in [0, limit).
# Random#rand's no-arg form now returns a real Float in [0, 1) (it used to return the raw 31-bit
# integer, a stale workaround from before Float worked). This is what next_float/prev_float's
# `num = -rand` round-trip specs need. Verified against MRI (values are deterministic here: a seeded LCG).
r = rand
p(r.class)                       # Float
p(r >= 0.0 && r < 1.0)           # true
n = rand(10)
p(n.class)                       # Integer
p(n >= 0 && n < 10)              # true
p(rand(1.0).class)               # Float
p(rand(2.5) < 2.5)               # true
# the next_float/prev_float round-trip the specs exercise
num = -rand
p(num.prev_float.next_float == num)   # true
# Random.rand no-arg is also a Float in [0,1)
rr = Random.rand
p(rr.class)                      # Float
p(rr >= 0.0 && rr < 1.0)         # true
# integer limit still bounded
p(Random.rand(100) < 100)        # true
