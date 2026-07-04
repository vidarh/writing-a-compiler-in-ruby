module S13
  class A
    def foo(a); a << "A#foo"; end
    def self.foo(a); a << "A.foo"; end
  end
  class B < A
    def self.foo(a); a << "B.foo"; super(a); end
  end
end
p S13::B.foo([])
