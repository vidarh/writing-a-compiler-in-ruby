
class Foo
  def foo= value
      puts "foo="
  end
  
  def foo
    puts "foo"
  end
end

f = Foo.new
f.foo= 5
f.foo

