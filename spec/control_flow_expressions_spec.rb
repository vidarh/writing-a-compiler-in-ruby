require_relative '../rubyspec/spec_helper'

# KNOWN_ISSUES #1: Control flow as expressions (PRIMARY BLOCKER)

describe "Control flow as expressions" do
  it "works in assignments with if" do
    x = if true; 42; end
    x.should == 42
  end

  it "should support method chaining on if expression results" do
    result = if true; "hello"; end.upcase
    result.should == "HELLO"
  end

  it "should support if expressions in array literals" do
    arr = [if true; 1; end, 2, 3]
    arr.should == [1, 2, 3]
  end

  it "should support arithmetic with if expression results" do
    result = (if true; 10; end) + 5
    result.should == 15
  end

  it "should support method calls on case expression results" do
    x = 1
    result = case x; when 1; "one"; end.upcase
    result.should == "ONE"
  end
end
