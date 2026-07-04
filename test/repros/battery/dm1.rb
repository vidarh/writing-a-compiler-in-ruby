class K3; end
K3.send(:define_method, :greet) do |name|
  "hi " + name
end
p K3.new.greet("bob")
# method_missing fallback still works
begin
  K3.new.nope
rescue => e
  p e.class
end
# user method_missing override
class K4
  def method_missing(sym, *a); [:mm, sym, a]; end
end
p K4.new.zap(1)
