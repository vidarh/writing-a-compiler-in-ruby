require_relative '../rubyspec/spec_helper'

describe "While loops" do
  it "executes the body while condition is true" do
    i = 0
    while i < 3
      i = i + 1
    end
    i.should == 3
  end

  it "returns nil from a while loop" do
    i = 0
    result = while i < 3
      i = i + 1
    end
    result.should == nil
  end

  it "supports break to exit early" do
    i = 0
    while i < 10
      i = i + 1
      break if i == 5
    end
    i.should == 5
  end
end
