def m(a, b, *c, d, e) [a, b, c, d, e] end
class BadE; def to_a; 1; end; end
class NilE; def to_a; nil; end; end
x = NilE.new
p m(1, 2, *x, 4)
y = BadE.new
p m(1, 2, *y, 4)
p "done"
