def m(*a); a; end
class MockA
  def method_missing(sym, *args); 1; end
  def respond_to?(sym); true; end
end
x = MockA.new
p m(*x)
p "done"
