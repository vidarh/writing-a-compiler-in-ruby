# Negative float literal with |x|<1 (e.g. -0.5) kept its sign: Int.expect turned "-0" into 0, so the
# float string wrongly became "0.5". Number.expect now restores the '-' when neg && i==0. Also -0.0.
p((-0.5).floor)   # -1
p((-0.7).ceil)    # 0
p([-0.5, -0.25, -0.9].length)  # 3
a = -0.5
p(a.floor)        # -1
