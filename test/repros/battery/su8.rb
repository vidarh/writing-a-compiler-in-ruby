module Outer14
  module S14
    class A
      def self.foo(a); a << "A.foo"; end
      def self.bar(a); a << "A.bar"; foo(a); end
    end
    class B < A
      def self.foo(a); a << "B.foo"; super(a); end
      def self.bar(a); a << "B.bar"; super(a); end
    end
  end
end
p Outer14::S14::B.foo([])
p Outer14::S14::B.bar([])
