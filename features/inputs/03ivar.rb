
# Tests access to instance vars, as well as verifies that #initialize gets caled.

class Foo

  def initialize
    @var = "hello"
  end

  def var
    @var
  end
end

f = Foo.new

printf "%s\n",f.var
