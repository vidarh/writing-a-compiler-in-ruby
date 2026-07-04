class Recv8
  def []=(a, b); p [a, b]; end
end
class BadB; def to_a; 1; end; end
o = Recv8.new
x = BadB.new
o[*x] = 1
p "done"
