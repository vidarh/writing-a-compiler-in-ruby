# eql? is type-strict where == is not: 1.eql?(1.0) is false though 1 == 1.0. Integer#eql? (type
# check then value compare, fixnum+bignum), Float#eql? (type-strict), Array#eql? (element-wise
# #eql?, NOT ==), and Struct#eql? (element-wise via Array#eql?). Guards these paths against
# layout-sensitive miscompiles. Values verified vs MRI.
p(1.eql?(1))            # true
p(1.eql?(1.0))          # false
p(1998.eql?(1998.0))    # false
p((2**40).eql?(2**40))  # true  (bignum, value compare)
p(1.0.eql?(1))          # false
p([1].eql?([1.0]))      # false
p([1, 2].eql?([1, 2]))  # true
S = Struct.new(:a, :b, :c)
p(S.new("H", "A", 1998).eql?(S.new("H", "A", 1998.0)))  # false
p(S.new("H", "A", 1998).eql?(S.new("H", "A", 1998)))    # true
p(S.new("H", "A", 1998) == S.new("H", "A", 1998.0))     # true  (== is lenient)
