# Array#eql? must terminate on cyclic (self-referential) arrays instead of recursing forever
# (-> stack overflow / SIGSEGV). Mirrors Array#=='s identity short-circuit + recursion guard.
# Regression guard: the element-wise-eql? rewrite originally lacked the guard and segfaulted here.
a = []
a << a                      # a = [a], contains itself
p(a.eql?([a]))              # true  (identity via the back-edge)
p(a.eql?([[a]]))            # true

back = []
forth = [back]
back << forth               # mutual cycle: back=[forth], forth=[back]
p(back.eql?(a))             # true  (needs the @__eql_comparing guard, not just identity)

x = []
x << x << x                 # x = [x, x]
p(x.eql?([x, x]))           # true
p(x.eql?(a))                # false (size differs)
