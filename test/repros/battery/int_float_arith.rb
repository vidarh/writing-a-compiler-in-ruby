# Integer +,-,*,/,%,remainder,div with a Float operand must coerce (they returned a bare Float.new,
# whose stub initialize leaves the raw double = 0x0000000100000001 = 2.1219957915e-314 garbage).
# Plus Float#%, remainder, and ** (integer exponent). Verified vs MRI.
p(5 - 2.5)              # 2.5
p(3 * 1.5)              # 4.5
p(10 / 4.0)             # 2.5
p(5 + 2.5)              # 7.5
p(5 % 2.0)              # 1.0
p(5.remainder(2.0))     # 1.0
p(5.div(2.0))           # 2
p(2.5 ** 2)             # 6.25
p(2.0 ** -1)            # 0.5
p(7.5 % 2.0)            # 1.5
p((1..3).map { |i| i / 2.0 })  # [0.5, 1.0, 1.5]
p(2.0 ** 10)           # 1024.0
p(10.0 ** 60 > 1.0e59) # true  -- large exponent must be FAST (O(log n) squaring, not O(n))
