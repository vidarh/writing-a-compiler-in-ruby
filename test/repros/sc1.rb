# safe-navigation (&.) followed by a comma list must not bind the comma into
# the method slot (dot-comma normalization must cover :safe_callm like :callm).
# Expected output:
#   [3, 9]
#   3 9
class R
  def m
    3
  end
end
r = R.new
a, b = r&.m, 9
puts [a, b].inspect

def f(x, y)
  puts "#{x} #{y}"
end
f r&.m, 9
