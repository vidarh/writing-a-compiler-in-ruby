class K9; end
K9.send(:define_method, :greet) do |name|
  "hi " + name
end
p K9.new.greet("bob")
