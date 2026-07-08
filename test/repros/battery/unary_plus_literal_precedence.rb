# A unary + directly before a numeric literal binds to the literal, so a following method call applies
# to the (positive) literal: +2.5.round parses as (+2.5).round, NOT +(2.5.round). Previously the lexer
# folded a negative literal for `-` but left `+` as a prefix operator over the whole postfix chain, so
# `+2.5e20.round(-20).should ...` became +(chain) -> "undefined method '+@' for true". Infix +, unary
# + on a non-literal (which must still dispatch #+@), and the ambiguous command-call forms are
# unaffected. Verified against MRI.
def val; true; end
p(+5.abs.val)              # true   <- the regression guard (was +@-on-true)
p(+2.5e20.round(-20))      # 300000000000000000000
p(+3.5.round)              # 4
p(+5)                      # 5
p(+3.5)                    # 3.5
# infix + and arithmetic unaffected
p(1 + 2)                   # 3
a = 2
p(a + 3)                   # 5
p(a +3)                    # 5
b = +4 + 5
p(b)                       # 9
# unary + on a non-literal still dispatches #+@
class Plusish
  def +@; "plusat"; end
  def +(o); "plus"; end
end
q = Plusish.new
p(+q)                      # "plusat"
p(q + 1)                   # "plus"
v = 7
p(+v)                      # 7
p([1, 2, 3].map { |n| +n })  # [1, 2, 3]
