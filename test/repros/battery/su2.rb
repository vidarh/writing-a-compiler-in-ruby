class A10
  def self.foo(a); a << "A.foo"; end
end
class B10 < A10
  def self.foo(a); a << "B.foo"; super(a); end
end
p B10.foo([])
