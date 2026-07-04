module S16
  class A
    def self.foo(a); a << "A.foo"; end
    def self.bar(a); a << "A.bar"; foo(a); end
  end
  class B < A
    def self.foo(a); a << "B.foo"; super(a); end
    def self.bar(a); a << "B.bar"; super(a); end
  end
end
p S16::B.bar([])
