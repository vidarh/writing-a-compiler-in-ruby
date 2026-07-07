# Float#arg / #angle / #phase (aliases): the complex argument of a real number. 0 for a positive
# value (including +0.0 and +Infinity), Math::PI for a negative value (including -0.0 and -Infinity),
# and self (NaN) for NaN. The -0.0 case is the subtle one: it compares == 0.0 yet must return PI, so
# the sign of a zero is read from 1.0/self. Verified against MRI.
inf = 1.0 / 0.0
nan = 0.0 / 0.0
p(1.0.arg)               # 0
p(0.0.arg)               # 0
p(inf.arg)               # 0
p((-1.0).arg)            # 3.141592653589793
p((-0.0).arg)            # 3.141592653589793  <- negative zero
p((0.0 - inf).arg)       # 3.141592653589793
p(nan.arg.nan?)          # true
p(nan.arg.equal?(nan))   # true   (returns self)
# aliases behave identically
p((-0.0).angle)          # 3.141592653589793
p((-0.0).phase)          # 3.141592653589793
p(2.0.angle)             # 0
p(2.0.phase)             # 0
