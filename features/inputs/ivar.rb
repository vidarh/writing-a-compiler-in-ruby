
# Check that instance variables are stored in the right slots
# 

class Ivar

  def initialize
    @foo = "foo"
    @bar = "bar"
    @baz = 1
  end

  def test
    puts @foo
    puts @bar
    puts @baz
  end
end

class IvarSub < Ivar

  def initialize
    @a = "A"
    @b = "B"
    @c = "C"
  end

  def test2
    puts @a
    puts @b
    puts @c
  end
end

i = Ivar.new
i.test

i = IvarSub.new
i.test
i.test2
