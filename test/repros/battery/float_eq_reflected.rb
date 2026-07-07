# Float#== deferred to `other == self` when the operand is not numeric, so a type with a custom
# == still matches (MRI Numeric#== fallback), instead of always returning false. Object#== is
# identity so a plain object stops the delegation without looping. Must not break the common cases
# (Float/Integer operands, containers) or NaN semantics.
p(1.0 == 1)                   # true
p(1.0 == 1.5)                 # false
p(1.0 == "x")                 # false
p(1.0 == nil)                 # false
p(1.5 == :sym)               # false
p([1.0, 2.0] == [1.0, 2.0])  # true
p(1.0 == Rational(1, 1))     # true
p((0.0 / 0.0) == (0.0 / 0.0)) # false (NaN != NaN)
