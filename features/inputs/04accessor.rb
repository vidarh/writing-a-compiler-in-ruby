
class Foo
  attr_accessor :bar

  def initialize
    @bar = "Hello\n"
  end
end

foo = Foo.new
puts foo.bar
