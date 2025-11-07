require_relative '../rubyspec/spec_helper'

# KNOWN_ISSUES #1: Control flow as expressions (PRIMARY BLOCKER)

describe "Control flow as expressions" do
  it "works in assignments with if" do
    x = if true; 42; end
    x.should == 42
  end

  it "should return value from if as method return" do
    def test_if_return
      if true; 42; end
    end
    test_if_return.should == 42
  end

  it "supports if with method chaining" do
    def test_if_to_s
      if true; 42; end.to_s
    end
    test_if_to_s.should == "42"
  end

  it "supports method chaining on if result" do
    result = (if true; 42; end).to_s
    result.should == "42"
  end

  it "supports if in array literals" do
    arr = [1, if true; 2; end, 3]
    arr.should == [1, 2, 3]
  end

  it "supports arithmetic with if result" do
    result = (if true; 10; end) + 5
    result.should == 15
  end

  it "supports method chaining on case result" do
    result = (case 1; when 1; "x"; end).upcase
    result.should == "X"
  end
end
