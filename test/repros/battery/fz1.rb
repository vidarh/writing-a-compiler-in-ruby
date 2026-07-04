obj = Object.new
obj.freeze
l = -> { def obj.foo; end }
begin
  l.call
  p "no error"
rescue => e
  p e.class
end
