def it3; yield; end
it3 do
  obj = Object.new
  l = -> { def obj.foo; "F"; end }
  l.call
  p obj.foo
end
