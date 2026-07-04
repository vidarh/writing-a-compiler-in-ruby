def it3; yield; end
it3 do
  obj = Object.new
  class << obj
    l = -> { def foo; end }
    p l.class
  end
  p "done"
end
