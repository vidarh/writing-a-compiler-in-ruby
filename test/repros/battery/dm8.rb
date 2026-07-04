class K10; end
K10.send(:define_method, :greet) do |name| "hi " + name end
p K10.new.greet("bob")
begin
  K10.new.nope
rescue => e
  p e.class
end
