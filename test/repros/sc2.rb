# Safe-navigation shape matrix around the dot-comma normalization.
# NOTE: `s&.x, c = 1, 2` (safe-nav in an MLHS target) is a SyntaxError in MRI,
# so it is deliberately absent.
# Expected output:
#   plain: 3
#   nilrecv:
#   args: [4, 9]
#   setter: 7
#   nil-mlhs: [nil, 5]
class S
  attr_accessor :x
  def m
    3
  end
  def plus(v)
    3 + v
  end
end
s = S.new
n = nil

puts "plain: #{s&.m}"
puts "nilrecv: #{n&.m}"
a, b = s&.plus(1), 9
puts "args: #{[a, b].inspect}"
s&.x = 7
puts "setter: #{s.x}"
d, e = n&.m, 5
puts "nil-mlhs: #{[d, e].inspect}"
