def m(*a); a; end
class NilToA
  def to_a; nil; end
end
x = NilToA.new
p m(*x)
p "done"
