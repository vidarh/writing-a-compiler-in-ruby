def it3; yield; end
def m(*a); a; end
class MockB
  def method_missing(sym, *args); 1; end
  def respond_to?(sym); true; end
end
it3 do
  x = MockB.new
  l = -> { m(*x) }
  begin
    p l.call
  rescue TypeError => e
    p e.class
  end
end
p "done"
