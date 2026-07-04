obj = Object.new
class << obj
  l = -> { def foo; end }
  p l.class
end
p "done"
