def it3; yield; end
it3 do
  obj = Object.new
  def obj.foo; "F"; end
  p obj.foo
end
