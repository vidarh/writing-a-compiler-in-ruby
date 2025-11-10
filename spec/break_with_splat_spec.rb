require_relative '../rubyspec/spec_helper'

# Break with splat operator fails to parse
# See TODO.md Language Spec Compilation Failures #4
#
# When using splat with break statement, parser leaves two separate
# expressions on value stack instead of combining them.

describe "Break with splat operator" do
  it "works with break and array splat" do
    result = loop do
      break *[1, 2]
    end
    # In Ruby, break *[1, 2] returns an array [1, 2]
    result.should == [1, 2]
  end

  it "works with break and single value splat" do
    result = loop do
      arr = [42]
      break *arr
    end
    result.should == [42]
  end

  it "works with next and splat" do
    result = [1, 2, 3].map do |x|
      next *[x * 2] if x > 1
      x
    end
    result.should == [1, 4, 6]
  end
end
