module Outer15
  module S15
    class A
      def self.foo(a); a << "A.foo"; end
      def self.bar(a); a << "A.bar"; foo(a); end
    end
    class B < A
      def self.foo(a); a << "B.foo"; super(a); end
    end
  end
end
p Outer15::S15::B.bar([])
