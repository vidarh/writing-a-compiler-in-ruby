
class Foo

  def bar
    puts("test")
  end
end

def test
  f = Foo.new
  f.bar
end

test
