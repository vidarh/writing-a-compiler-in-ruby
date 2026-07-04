module S9
  class A
    def self.foo(a); a << "A.foo"; end
  end
  class B < A
    def self.foo(a); a << "B.foo"; super(a); end
  end
end
p S9::B.foo([])
