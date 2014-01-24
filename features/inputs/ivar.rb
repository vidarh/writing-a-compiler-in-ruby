
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
#    puts @baz
  end
end

i = Ivar.new
i.test
