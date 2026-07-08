# Unary minus on the built-in numerics via both `-x` (which dispatches to #-@ since the unary-minus
# codegen fix) and an explicit send(:-@). Integer/Float/Rational negate directly. (Numeric#-@ itself --
# coerce(0) then subtract -- is exercised by core/numeric/uminus via a mock; a REAL Numeric SUBCLASS's
# -@ currently miscompiles under the pre-existing Numeric-subclass dispatch bug, so it is deliberately
# not exercised here.) Verified vs MRI.
p(-5)                        # -5
p(-(-5))                     # 5
p(-2.5)                      # -2.5
p(100.send(:-@))             # -100
p((-100).send(:-@))          # 100
p(2147483648.send(:-@))      # -2147483648
p(Rational(3, 4).send(:-@).to_s)   # "-3/4"
p((-Rational(3, 4)).to_s)          # "-3/4"
