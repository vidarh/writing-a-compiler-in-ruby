# Numeric base defaults: #+@ is identity, #integer? is false (Integer overrides -> true), and
# #conj/#conjugate return self (the conjugate of a real number is itself). Float carries its own copies
# since it is not a Numeric subclass here. Verified vs MRI.
class N < Numeric; end
o = N.new
p(o.send(:+@).equal?(o))    # true   (Numeric#+@)
p(o.integer?)               # false  (Numeric#integer?)
p(o.conj.equal?(o))         # true   (Numeric#conj)
p(o.conjugate.equal?(o))    # true

p(5.integer?)               # true   (Integer overrides)
p(5.0.integer?)             # false  (Float)
p(Rational(3, 4).integer?)  # false
p(20.conj.equal?(20))       # true
p(398.72.conjugate == 398.72)  # true
p(5.send(:+@))              # 5
p(5.0.send(:+@))            # 5.0
