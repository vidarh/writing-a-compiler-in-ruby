obj = Object.new
l = -> { def obj.foo; "F"; end }
l.call
p obj.foo
