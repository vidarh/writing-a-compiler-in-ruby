module Outer12
  module S12
    class A
      def foo(a); a << "A#foo"; end
      def self.foo(a); a << "A.foo"; end
    end
    class B < A
      def self.foo(a); a << "B.foo"; super(a); end
    end
  end
end
p Outer12::S12::B.foo([])
