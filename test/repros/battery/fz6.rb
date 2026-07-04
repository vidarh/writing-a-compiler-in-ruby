def it3; yield; end
it3 do
  obj = Object.new
  obj.to_s
  l = -> { def obj.foo; end }
  l.call
  p "done"
end
