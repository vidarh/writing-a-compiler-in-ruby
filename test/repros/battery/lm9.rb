class Recv9
  def m=(a); p a; end
end
class BadC; def to_a; 1; end; end
o = Recv9.new
x = BadC.new
o.send(:m=, *x)
p "done"
