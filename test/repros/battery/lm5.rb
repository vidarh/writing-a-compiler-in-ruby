def m(a) a end
class MockC
  def method_missing(sym, *args); 1; end
  def respond_to?(sym); true; end
end
x = MockC.new
p m(*x)
p "done"
