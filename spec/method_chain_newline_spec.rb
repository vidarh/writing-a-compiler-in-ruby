require_relative '../rubyspec_helper'

describe "Method chaining across newlines" do
  it "allows . at start of line" do
    def foo; 42; end
    result = foo()
      .to_s
    result.should == "42"
  end

  it "allows multiple chained methods across newlines" do
    result = [1, 2, 3]
      .reverse
      .first
    result.should == 3
  end

  it "works with parentheses" do
    result = (42)
      .to_s
    result.should == "42"
  end
end
