# Unary minus `-x` dispatches to the operand's own #-@ (it was previously lowered to `0 - x`, which
# called Integer#- and silently ignored a custom -@). Built-in numeric negation is unchanged because
# Integer/Float/Rational/Complex all define -@. Negative numeric literals are folded by the lexer, so
# only `-<expression>` exercises this path. Verified vs MRI.

# A custom object's -@ is honoured
class Negatable
  def -@; "negated"; end
end
p(-Negatable.new)      # "negated"

# built-in numeric negation still works
x = 5
p(-x)                  # -5
y = 3.5
p(-y)                  # -3.5
n = -2                 # literal fold; n == -2
p(-n)                  # 2  -- negate a negative variable

# negation of a non-literal expression, and double negation
a = 10
b = 3
p(-(a + b))            # -13
p(-(-x))               # 5

# Rational / Complex dispatch to their own -@
r = Rational(3, 4)
p((-r).to_s)           # "-3/4"
c = Complex(1, -2)
p((-c).to_s)           # "-1+2i"
