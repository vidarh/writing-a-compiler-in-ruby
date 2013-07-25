

class Foo

  def initialize
  end

  def foo
    puts "foo"
  end

  def bar arg
    puts arg
  end
end

f = Foo.new
f.foo
f.bar("bar")
