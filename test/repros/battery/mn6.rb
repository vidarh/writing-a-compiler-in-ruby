module Outer9
  module Inner9
    def self.hi; "nested-ok"; end
  end
  class Deep9
    def v; 5; end
  end
end
p Outer9::Inner9.hi
p Outer9::Deep9.new.v
module Outer9::Direct9
  def self.d; "direct"; end
end
p Outer9::Direct9.d
