# Body-shape normalization matrix (R1). Expected output:
#   A:body A:ensure
#   B:rescued
#   C:1 {:k=>2} C:ensure
#   D:blockvar
#   E:5 E:ensure
#   F:lambda-rescued
#   G:42
def a
  print "A:body "
ensure
  puts "A:ensure"
end
a

def b
  raise "x"
rescue
  puts "B:rescued"
end
b

def c(x, k: 2)
  print "C:#{x} #{{:k => k}.inspect} "
ensure
  puts "C:ensure"
end
c(1)

def block
  "D:blockvar"
end
def d
  block
end
puts d

def e_(x = 5)
  print "E:#{x} "
rescue
  puts "E:rescued"
ensure
  puts "E:ensure"
end
e_

f = lambda do
  begin
    raise "y"
  rescue
    puts "F:lambda-rescued"
  end
end
f.call

def g(v = 40)
  return v + 2
ensure
  nil
end
puts "G:#{g}"
