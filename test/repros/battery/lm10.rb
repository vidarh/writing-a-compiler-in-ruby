class RecvA
  def []=(a, b); [a, b]; end
end
class BadD; def to_a; nil; end; end
o = RecvA.new
x = BadD.new
r = (o[*x] = 1)
p r
p "done"
