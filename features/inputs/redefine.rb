
class Foo
  def hello
    puts "hello"
  end

  def world
    puts "world"
  end
end

# Bar does not override anything, so it should keep acting like Foo.
class Bar < Foo
end

# Baz overrides, so when Foo#hello is overriden, Baz#hello should remain
# overriden
class Baz < Foo
  def hello
    puts "crazy"
  end
end


puts "Foo"
f = Foo.new
f.hello
f.world
puts

puts "Bar"
b = Bar.new
b.hello
b.world  
puts

puts "Baz"
z = Baz.new
z.hello
z.world
puts

class Foo
  def hello
    puts "goodbye cruel"
  end
end

puts "Foo:"
f.hello
f.world
puts

puts "Bar should be identical to Foo:"
b.hello
b.world
puts

puts "Baz overrode Foo#hello, so should be identical to Baz above"
z.hello
z.world
