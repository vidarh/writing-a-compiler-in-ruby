
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

# Necessary because recent changes means printf isn't working
%s(printf "%s\n" (callm (callm f var) __get_raw))
