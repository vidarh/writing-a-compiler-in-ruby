def m2(a, b); [a, b]; end
class BadA; def to_a; 1; end; end
x = BadA.new
p m2(*x, 9) rescue p :caught1
p m2(9, *x) rescue p :caught2
p [*x, 1] rescue p :caught3
p "done"
