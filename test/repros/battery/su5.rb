module Outer11
  module S11
    class A
      def self.foo(a); a << "A.foo"; end
    end
    class B < A
      def self.foo(a); a << "B.foo"; super(a); end
    end
  end
end
p Outer11::S11::B.foo([])
