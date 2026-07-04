begin
  class << 1; self; end
rescue TypeError => e
  p e.class
end
begin
  class << :sym; self; end
rescue TypeError => e
  p e.class
end
obj = Object.new
k = class << obj; self; end
p k.class
p "done"
