class A9
  def self.foo; "A9.foo"; end
end
class B9 < A9
  def self.foo; super; end
end
p B9.foo
