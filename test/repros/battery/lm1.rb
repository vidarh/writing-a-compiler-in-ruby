def m(*a); a; end
class BadToA
  def to_a; 1; end
end
x = BadToA.new
p m(*x)
p "done"
